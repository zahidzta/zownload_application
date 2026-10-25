// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { waitFor } from '@testing-library/react'
import { expect, test, vi } from 'vitest'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createMemoryMockStorage } from '../../src/transport/mockStorage'
import { createRuntimeTransport, usesDesktopNativeTransport } from '../../src/transport/runtime'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'

test('native development preview uses offline analysis but sends durable activity to the native boundary', async () => {
  const previewStorage = createMemoryMockStorage()
  const preview = createSimulatorTransport({ storage: previewStorage })
  const nativeStorage = createMemoryMockStorage()
  // This stand-in records which commands reach the Rust boundary; a native relaunch is checked separately.
  const native = createSimulatorTransport({ clock: createManualSimulatorClock(), storage: nativeStorage })
  const previewCall = vi.spyOn(preview, 'call')
  const previewOn = vi.spyOn(preview, 'on')
  const nativeCall = vi.spyOn(native, 'call')
  const nativeOn = vi.spyOn(native, 'on')
  const transport = createRuntimeTransport({
    native: true, development: true, nativeTransport: native, simulatorTransport: preview,
  })
  const flow = createDownloadFlowStore(transport)
  const off = flow.getState().connectActivity()
  await waitFor(() => expect(flow.getState().settings).not.toBeNull())
  flow.getState().setUrl(analysisUrls.single)
  await flow.getState().analyze()
  expect(flow.getState().step).toBe('download')
  const id = await flow.getState().enqueue()
  expect(id).toMatch(/^[0-9a-f-]{36}$/)
  await waitFor(() => expect(flow.getState().queueItems.map((item) => item.id)).toEqual([id]))
  expect(flow.getState().queueItems[0].status).toBe('queued')
  await flow.getState().saveSettings({ language: 'es', zipPlaylists: true })
  await flow.getState().cancelQueueItem(id!)
  await waitFor(() => expect(flow.getState().queueItems).toEqual([]))
  expect(nativeStorage.load()?.settings).toMatchObject({ language: 'es', zipPlaylists: true })
  expect(nativeStorage.load()?.queue).toEqual([])
  expect(previewStorage.load()?.queue ?? []).toEqual([])
  expect(previewCall.mock.calls.map(([name]) => name)).toEqual(['analyze_url'])
  expect(previewOn).not.toHaveBeenCalled()
  expect(nativeOn.mock.calls.map(([name]) => name)).toEqual([
    'queue:item-updated', 'queue:item-removed', 'history:changed', 'error-notifications:changed',
  ])
  expect(nativeCall.mock.calls.map(([name]) => name)).toEqual(expect.arrayContaining([
    'get_queue', 'get_history', 'get_error_notifications', 'get_settings',
    'enqueue_download', 'set_settings', 'remove_download',
  ]))
  off()
})

test('production native analysis stays on Rust and browser preview stays isolated', async () => {
  const native = createSimulatorTransport()
  const preview = createSimulatorTransport()
  const nativeCall = vi.spyOn(native, 'call')
  const previewCall = vi.spyOn(preview, 'call')
  const production = createRuntimeTransport({
    native: true, development: false, nativeTransport: native, simulatorTransport: preview,
  })
  expect(production).toBe(native)
  await production.call('analyze_url', { url: analysisUrls.single })
  expect(nativeCall).toHaveBeenCalledWith('analyze_url', { url: analysisUrls.single })
  expect(previewCall).not.toHaveBeenCalled()
  const browser = createRuntimeTransport({
    native: false, development: true, nativeTransport: native, simulatorTransport: preview,
  })
  expect(browser).toBe(preview)
  expect(usesDesktopNativeTransport(true, 'Mozilla/5.0 (Windows NT 10.0)')).toBe(true)
  expect(usesDesktopNativeTransport(true, 'Mozilla/5.0 (Linux; Android 15)')).toBe(false)
  expect(usesDesktopNativeTransport(false, 'Mozilla/5.0 (Windows NT 10.0)')).toBe(false)
})
