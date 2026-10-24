// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { AppView } from '../../src/App'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createMemoryMockStorage } from '../../src/transport/mockStorage'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'
import type { ErrorNotification, HistoryEntry, QueueItem } from '../../shared/contract'

const singleRequest = {
  url: analysisUrls.single, format: 'mp3' as const,
  quality: { type: 'audio' as const, bitrate: 128 }, isPlaylist: false,
}

test('a queue event during startup snapshot wins over the stale response', async () => {
  const clock = createManualSimulatorClock()
  const simulator = createSimulatorTransport({ clock })
  const call = simulator.call.bind(simulator)
  let resolveStale!: (items: QueueItem[]) => void
  const stale = new Promise<QueueItem[]>((resolve) => { resolveStale = resolve })
  let queueReads = 0
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => {
      if (command === 'get_queue' && ++queueReads === 1) return stale
      return call(command, args)
    }) as AppTransport['call'],
  }
  const flow = createDownloadFlowStore(transport)
  const off = flow.getState().connectActivity()
  await waitFor(() => expect(queueReads).toBe(1))
  const id = await transport.call('enqueue_download', { request: singleRequest })
  clock.advanceBy(0)
  expect(flow.getState().queueItems.map((item) => item.id)).toEqual([id])
  resolveStale([])
  await waitFor(() => expect(queueReads).toBe(2))
  expect(flow.getState().queueItems.map((item) => item.id)).toEqual([id])
  off()
})

test('history and notification change events supersede stale startup reads', async () => {
  const clock = createManualSimulatorClock()
  const simulator = createSimulatorTransport({ clock, outcomes: { [analysisUrls.playlist]: 'partial' } })
  const call = simulator.call.bind(simulator)
  let resolveOldHistory!: (entries: HistoryEntry[]) => void
  let resolveOldNotifications!: (notes: ErrorNotification[]) => void
  const oldHistory = new Promise<HistoryEntry[]>((resolve) => { resolveOldHistory = resolve })
  const oldNotifications = new Promise<ErrorNotification[]>((resolve) => { resolveOldNotifications = resolve })
  let historyReads = 0
  let notificationReads = 0
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => {
      if (command === 'get_history' && ++historyReads === 1) return oldHistory
      if (command === 'get_error_notifications' && ++notificationReads === 1) return oldNotifications
      return call(command, args)
    }) as AppTransport['call'],
  }
  const flow = createDownloadFlowStore(transport)
  const off = flow.getState().connectActivity()
  await waitFor(() => expect(historyReads).toBe(1))
  await waitFor(() => expect(notificationReads).toBe(1))
  await transport.call('enqueue_download', { request: {
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'max' }, isPlaylist: true,
  } })
  clock.advanceBy(8000)
  await waitFor(() => expect(flow.getState().historyEntries).toHaveLength(1))
  await waitFor(() => expect(flow.getState().notifications).toHaveLength(1))
  resolveOldHistory([])
  resolveOldNotifications([])
  await Promise.resolve()
  expect(flow.getState().historyEntries).toHaveLength(1)
  expect(flow.getState().notifications).toHaveLength(1)
  off()
})

test('connection is shared, cleans up, and a new UI store reloads history and notifications', async () => {
  const clock = createManualSimulatorClock()
  const storage = createMemoryMockStorage()
  const simulator = createSimulatorTransport({ clock, storage, outcomes: { [analysisUrls.playlist]: 'partial' } })
  const on = vi.spyOn(simulator, 'on')
  const first = createDownloadFlowStore(simulator)
  const offOne = first.getState().connectActivity()
  const offTwo = first.getState().connectActivity()
  await waitFor(() => expect(on).toHaveBeenCalledTimes(4))
  const id = await simulator.call('enqueue_download', { request: {
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'min' }, isPlaylist: true,
  } })
  clock.advanceBy(8000)
  await waitFor(() => expect(first.getState().historyEntries).toHaveLength(1))
  await waitFor(() => expect(first.getState().notifications).toMatchObject([{ id }]))
  expect(first.getState().queueItems).toEqual([])
  offOne()
  offTwo()
  offTwo()
  await simulator.call('enqueue_download', { request: singleRequest })
  clock.advanceBy(0)
  expect(first.getState().queueItems).toEqual([])

  const restarted = createSimulatorTransport({ storage, clock: createManualSimulatorClock() })
  const second = createDownloadFlowStore(restarted)
  const disconnect = second.getState().connectActivity()
  await waitFor(() => expect(second.getState().historyEntries).toHaveLength(1))
  await waitFor(() => expect(second.getState().notifications).toMatchObject([{ id }]))
  await waitFor(() => expect(second.getState().queueItems).toMatchObject([{ status: 'paused' }]))
  await waitFor(() => expect(second.getState().settings).toMatchObject({ language: 'en', zipPlaylists: false }))
  disconnect()
})

test('unmount releases subscriptions while a startup snapshot remains pending', async () => {
  const simulator = createSimulatorTransport({ clock: createManualSimulatorClock() })
  const call = simulator.call.bind(simulator)
  let resolveQueue!: (items: QueueItem[]) => void
  const pending = new Promise<QueueItem[]>((resolve) => { resolveQueue = resolve })
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => command === 'get_queue' ? pending : call(command, args)) as AppTransport['call'],
  }
  const on = vi.spyOn(transport, 'on')
  const flow = createDownloadFlowStore(transport)
  const off = flow.getState().connectActivity()
  await waitFor(() => expect(on).toHaveBeenCalledTimes(4))
  off()
  off()
  await simulator.call('enqueue_download', { request: singleRequest })
  expect(flow.getState().queueItems).toEqual([])
  resolveQueue(await simulator.call('get_queue', {}))
  await Promise.resolve()
  expect(flow.getState().queueItems).toEqual([])
})

test('accepted enqueue stays accepted when the queue read fails, and retry loads it', async () => {
  const clock = createManualSimulatorClock()
  const simulator = createSimulatorTransport({ clock })
  const call = simulator.call.bind(simulator)
  let fail = true
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => {
      if (command === 'get_queue' && fail) {
        fail = false
        return Promise.reject({ code: 'no_internet', detail: 'Synthetic snapshot failure' })
      }
      return call(command, args)
    }) as AppTransport['call'],
  }
  const flow = createDownloadFlowStore(transport)
  flow.getState().setUrl(analysisUrls.single)
  await flow.getState().analyze()
  const id = await flow.getState().enqueue()
  expect(id).toMatch(/^[0-9a-f-]{36}$/)
  expect(flow.getState()).toMatchObject({ step: 'input', url: '', error: null, syncError: { code: 'no_internet' } })
  await flow.getState().retryActivity()
  expect(flow.getState().syncError).toBeNull()
  expect(flow.getState().queueItems.map((item) => item.id)).toEqual([id])
})

test('mounted app announces a translated snapshot error and offers retry', async () => {
  const clock = createManualSimulatorClock()
  const simulator = createSimulatorTransport({ clock })
  const call = simulator.call.bind(simulator)
  let fail = true
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => {
      if (command === 'get_queue' && fail) {
        fail = false
        return Promise.reject({ code: 'unknown', detail: null })
      }
      return call(command, args)
    }) as AppTransport['call'],
  }
  const flowStore = createDownloadFlowStore(transport)
  const props = { page: 'main' as const, onBack: () => {}, onToggleLocale: () => {}, onOpenSettings: () => {}, flowStore }
  const view = render(<AppView {...props} locale="en" />)
  expect((await screen.findByRole('alert')).textContent).toContain('Could not load download activity.')
  view.rerender(<AppView {...props} locale="es" />)
  expect(screen.getByRole('alert').textContent).toContain('No se pudo cargar la actividad')
  await userEvent.setup().click(screen.getByRole('button', { name: 'Reintentar la carga de actividad' }))
  await waitFor(() => expect(screen.queryByRole('alert')).toBeNull())
  view.unmount()
})
