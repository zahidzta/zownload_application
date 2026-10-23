// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { afterEach, expect, test, vi } from 'vitest'
import type { DownloadRequest, QueueItem } from '../../shared/contract'
import { analysisUrls } from '../../src/transport/fixtures'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'

afterEach(() => vi.unstubAllGlobals())

test('observed short video has contract-shaped metadata and an inline thumbnail', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)

  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.single })

  expect(result).toMatchObject({
    kind: 'single',
    url: analysisUrls.single,
    title: '10號風...',
    author: 'vgocyl',
    durationSec: 15,
    site: 'YouTube',
    videoHeights: [720, 360, 144],
    audioOutputBitrates: [320, 256, 192, 128],
  })
  expect(result.thumbnail).toMatch(/^data:image\/svg\+xml/)
  expect(result).not.toHaveProperty('estimates')
  expect(fetchSpy).not.toHaveBeenCalled()
})

test('pure playlist exposes all 17 observed titles without a remote image', async () => {
  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.playlist })

  expect(result.kind).toBe('playlist')
  if (result.kind !== 'playlist') throw new Error('Expected playlist')
  expect(result.itemCount).toBe(17)
  expect(result.itemTitles).toHaveLength(result.itemCount)
  expect(result.itemTitles).toContain('WING IT! - Blender Open Movie')
  expect(result.itemTitles).toContain('CHARGE - Blender Open Movie')
  expect(result.itemTitles.at(-1)).toBe('Elephants Dream')
  expect(result.thumbnail).toMatch(/^data:image\/svg\+xml/)
})

test('watch plus list resolves to its single video even when query order changes', async () => {
  const url = 'https://www.youtube.com/watch?list=PL6B3937A5D230E335&v=u9lj-c29dxI'
  const result = await createSimulatorTransport().call('analyze_url', { url })

  expect(result).toMatchObject({
    kind: 'single',
    url,
    title: 'WING IT! - Blender Open Movie',
    durationSec: 238,
    videoHeights: [1080, 720, 480, 360, 240, 144],
  })
})

test.each([
  [analysisUrls.invalid, 'invalid_url', "ERROR: [generic] 'not-a-url' is not a valid URL"],
  [analysisUrls.unsupported, 'unsupported_site', 'Synthetic offline scenario:'],
  [analysisUrls.notFound, 'not_found', 'HTTP Error 404: Not Found'],
  [analysisUrls.restricted, 'private_or_restricted', 'HTTP Error 401: Unauthorized'],
])('%s rejects with %s and diagnostic detail', async (url, code, detail) => {
  await expect(createSimulatorTransport().call('analyze_url', { url })).rejects.toMatchObject({
    code,
    detail: expect.stringContaining(detail),
  })
})

test('unknown inputs stay typed, and a caller cannot mutate stored fixture arrays', async () => {
  const transport = createSimulatorTransport()
  await expect(transport.call('analyze_url', { url: 'not another URL' })).rejects.toMatchObject({
    code: 'invalid_url',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })
  await expect(transport.call('analyze_url', { url: 'https://www.youtube.com/watch?v=other' })).rejects.toMatchObject({
    code: 'not_found',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })

  const first = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (first.kind !== 'playlist') throw new Error('Expected playlist')
  first.itemTitles[0] = 'Changed by caller'
  const second = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (second.kind !== 'playlist') throw new Error('Expected playlist')
  expect(second.itemTitles[0]).toBe('SINGULARITY - Painterly Space Adventure')
})

test('enqueue returns distinct ids and ordered queued snapshots for single and playlist requests', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const events: QueueItem[] = []
  await transport.on('queue:item-updated', item => { events.push(item) })
  const single: DownloadRequest = {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  }
  const playlist: DownloadRequest = {
    url: analysisUrls.playlist, format: 'mp3', quality: { type: 'max' }, isPlaylist: true,
  }

  const firstId = await transport.call('enqueue_download', { request: single })
  const secondId = await transport.call('enqueue_download', { request: playlist })
  expect(firstId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/)
  expect(secondId).not.toBe(firstId)

  const queue = await transport.call('get_queue', {})
  expect(queue).toEqual([
    {
      id: firstId, request: single, title: '10號風...', thumbnail: expect.stringMatching(/^data:image\/svg\+xml/),
      status: 'queued', progress: { kind: 'single', percent: 0 }, error: null,
    },
    {
      id: secondId, request: playlist, title: 'Official Blender Open Movies',
      thumbnail: expect.stringMatching(/^data:image\/svg\+xml/), status: 'queued',
      progress: { kind: 'playlist', done: 0, failed: 0, total: 17, currentTitle: null, currentPercent: 0 },
      error: null,
    },
  ])
  expect(events).toEqual([])
  clock.advanceBy(0)
  expect(events).toEqual(queue)
  expect(fetchSpy).not.toHaveBeenCalled()

  // Queue reads and event payloads must not let the UI change simulator state.
  queue[0].request.url = 'changed by caller'
  events[1].title = 'changed by listener'
  expect((await transport.call('get_queue', {}))[0].request.url).toBe(analysisUrls.single)
  expect((await transport.call('get_queue', {}))[1].title).toBe('Official Blender Open Movies')
})

test('queue subscriptions can be removed independently and repeatedly', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const first = vi.fn()
  const second = vi.fn()
  const unsubscribeFirst = await transport.on('queue:item-updated', first)
  const unsubscribeSecond = await transport.on('queue:item-updated', second)
  const request: DownloadRequest = {
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  }

  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(1)
  expect(second).toHaveBeenCalledTimes(1)

  unsubscribeFirst()
  unsubscribeFirst()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(1)
  expect(second).toHaveBeenCalledTimes(2)

  unsubscribeSecond()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(second).toHaveBeenCalledTimes(2)
  expect(await transport.call('get_queue', {})).toHaveLength(3)

  const removeOneCopy = await transport.on('queue:item-updated', first)
  const removeOtherCopy = await transport.on('queue:item-updated', first)
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(3)
  removeOneCopy()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(4)
  removeOtherCopy()
})

test('enqueue rejects invalid or mismatched requests without creating a queue item', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const listener = vi.fn()
  await transport.on('queue:item-updated', listener)
  await expect(transport.call('enqueue_download', { request: {
    url: analysisUrls.invalid, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  } })).rejects.toMatchObject({ code: 'invalid_url' })
  await expect(transport.call('enqueue_download', { request: {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  } })).rejects.toMatchObject({ code: 'unknown', detail: expect.stringContaining('Synthetic offline scenario:') })
  clock.advanceBy(0)
  expect(listener).not.toHaveBeenCalled()
  expect(await transport.call('get_queue', {})).toEqual([])
})
