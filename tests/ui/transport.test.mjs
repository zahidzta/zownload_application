// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import test, { after } from 'node:test'
import { createServer } from 'vite'

let rejectTauriImports = true
const vite = await createServer({
  configFile: false,
  server: { middlewareMode: true, hmr: false },
  appType: 'custom',
  plugins: [{
    name: 'reject-tauri-in-injection-entry',
    resolveId(source) {
      if (rejectTauriImports && (source.includes('@tauri-apps/api') || source.includes('shared/contract') || source.endsWith('/tauri'))) {
        throw new Error(`The injection entry imported Tauri: ${source}`)
      }
    },
  }],
})
after(() => vite.close())
const { createAppTransport } = await vite.ssrLoadModule('/src/transport/index.ts')
rejectTauriImports = false

test('injected command calls forward typed names, arguments, results, and rejection', async () => {
  const calls = []
  const unavailable = { code: 'no_internet', detail: null }
  const memory = {
    async call(command, args) {
      calls.push([command, args])
      if (command === 'get_queue') return []
      if (command === 'enqueue_download') return 'memory-item-1'
      throw unavailable
    },
    async on() { return () => {} },
  }
  const transport = createAppTransport(memory)
  const request = {
    url: 'https://example.test/video',
    format: 'mp3',
    quality: { type: 'audio', bitrate: 128 },
    isPlaylist: false,
  }

  assert.deepEqual(await transport.call('get_queue', {}), [])
  assert.equal(await transport.call('enqueue_download', { request }), 'memory-item-1')
  await assert.rejects(transport.call('get_settings', {}), (error) => error === unavailable)
  assert.deepEqual(calls, [
    ['get_queue', {}],
    ['enqueue_download', { request }],
    ['get_settings', {}],
  ])
})

test('event payloads and promised unsubscribe pass through the injected implementation', async () => {
  const listeners = new Map()
  const memory = {
    async call() { return undefined },
    async on(name, handler) {
      listeners.set(name, handler)
      return () => listeners.delete(name)
    },
  }
  const transport = createAppTransport(memory)
  const received = []
  const off = await transport.on('history:changed', (payload) => received.push(payload))
  assert.equal(typeof off, 'function')
  listeners.get('history:changed')(null)
  assert.deepEqual(received, [null])
  off()
  assert.equal(listeners.has('history:changed'), false)
})

test('Tauri adapter uses the existing contract helpers', async () => {
  const [{ tauriTransport }, { call, on }] = await Promise.all([
    vite.ssrLoadModule('/src/transport/tauri.ts'),
    vite.ssrLoadModule('/shared/contract.ts'),
  ])
  assert.equal(tauriTransport.call, call)
  assert.equal(tauriTransport.on, on)
})
