// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { AppView } from '../../src/App'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createMemoryMockStorage } from '../../src/transport/mockStorage'
import { createRuntimeTransport, usesDesktopNativeTransport } from '../../src/transport/runtime'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'

test('native development sends analysis and durable activity to the Rust boundary', async () => {
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
    native: true, nativeTransport: native, simulatorTransport: preview,
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
  flow.getState().setUrl(analysisUrls.playlist)
  await flow.getState().analyze()
  expect(flow.getState().result?.kind).toBe('playlist')
  flow.getState().setUrl('not-a-url')
  await flow.getState().analyze()
  expect(flow.getState().step).toBe('input')
  expect(flow.getState().error?.code).toBe('invalid_url')
  expect(nativeStorage.load()?.settings).toMatchObject({ language: 'es', zipPlaylists: true })
  expect(nativeStorage.load()?.queue).toEqual([])
  expect(previewStorage.load()?.queue ?? []).toEqual([])
  expect(previewCall).not.toHaveBeenCalled()
  expect(previewOn).not.toHaveBeenCalled()
  expect(nativeOn.mock.calls.map(([name]) => name)).toEqual([
    'queue:item-updated', 'queue:item-removed', 'history:changed', 'error-notifications:changed',
  ])
  expect(nativeCall.mock.calls.map(([name]) => name)).toEqual(expect.arrayContaining([
    'get_queue', 'get_history', 'get_error_notifications', 'get_settings', 'analyze_url',
    'enqueue_download', 'set_settings', 'remove_download',
  ]))
  off()
})

test('native analysis stays on Rust and browser preview stays isolated', async () => {
  const native = createSimulatorTransport()
  const preview = createSimulatorTransport()
  const nativeCall = vi.spyOn(native, 'call')
  const previewCall = vi.spyOn(preview, 'call')
  const production = createRuntimeTransport({ native: true, nativeTransport: native, simulatorTransport: preview })
  expect(production).toBe(native)
  await production.call('analyze_url', { url: analysisUrls.single })
  expect(nativeCall).toHaveBeenCalledWith('analyze_url', { url: analysisUrls.single })
  expect(previewCall).not.toHaveBeenCalled()
  const browser = createRuntimeTransport({
    native: false, nativeTransport: native, simulatorTransport: preview,
  })
  expect(browser).toBe(preview)
  expect(usesDesktopNativeTransport(true, 'Mozilla/5.0 (Windows NT 10.0)')).toBe(true)
  expect(usesDesktopNativeTransport(true, 'Mozilla/5.0 (Linux; Android 15)')).toBe(false)
  expect(usesDesktopNativeTransport(false, 'Mozilla/5.0 (Windows NT 10.0)')).toBe(false)
})

test('mounted native activity routes controls and reloads a translated failure', async () => {
  const clock = createManualSimulatorClock()
  const nativeStorage = createMemoryMockStorage()
  const previewStorage = createMemoryMockStorage()
  const native = createSimulatorTransport({ clock, storage: nativeStorage, outcomes: { [analysisUrls.single]: 'failed' } })
  const preview = createSimulatorTransport({ storage: previewStorage })
  const nativeCall = vi.spyOn(native, 'call')
  const previewCall = vi.spyOn(preview, 'call')
  const transport = createRuntimeTransport({ native: true, nativeTransport: native, simulatorTransport: preview })
  const flow = createDownloadFlowStore(transport)
  const props = { page: 'main' as const, onBack: () => {}, onToggleLocale: () => {}, onOpenSettings: () => {}, flowStore: flow }
  const view = render(<AppView {...props} locale="en" />)
  const user = userEvent.setup()
  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), analysisUrls.single)
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  await user.click(await screen.findByRole('button', { name: 'Download' }))
  await waitFor(() => expect(flow.getState()).toMatchObject({ step: 'input', url: '' }))
  act(() => clock.advanceBy(1000))
  await waitFor(() => expect(screen.getByRole('button', { name: 'Stop' }).hasAttribute('disabled')).toBe(false))
  await user.click(screen.getByRole('button', { name: 'Stop' }))
  act(() => clock.advanceBy(0))
  await waitFor(() => expect(screen.getByText('Paused')).not.toBeNull())
  await user.click(screen.getByRole('button', { name: 'Continue' }))
  act(() => clock.advanceBy(8000))
  await waitFor(() => expect(flow.getState().notifications).toHaveLength(1))
  expect(screen.getByText('No active downloads')).not.toBeNull()
  expect(nativeCall.mock.calls.map(([name]) => name)).toEqual(expect.arrayContaining([
    'analyze_url', 'enqueue_download', 'pause_download', 'resume_download', 'get_error_notifications',
  ]))
  expect(previewCall).not.toHaveBeenCalled()
  expect(previewStorage.load()?.queue ?? []).toEqual([])
  view.unmount()
  const reopened = createDownloadFlowStore(createSimulatorTransport({ storage: nativeStorage, clock: createManualSimulatorClock() }))
  const second = render(<AppView {...props} flowStore={reopened} locale="es" />)
  await waitFor(() => expect(reopened.getState().notifications).toHaveLength(1))
  expect(screen.getByRole('alert').textContent).toContain('Ocurrió un error.')
  second.unmount()
})
