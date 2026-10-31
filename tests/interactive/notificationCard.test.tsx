// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { AppView } from '../../src/App'
import { NotificationCard } from '../../src/components/NotificationCard'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createMemoryMockStorage } from '../../src/transport/mockStorage'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'

const request = {
  url: analysisUrls.single, format: 'mp3' as const,
  quality: { type: 'audio' as const, bitrate: 128 }, isPlaylist: false,
}
const viewProps = { page: 'main' as const, onBack: () => {}, onToggleLocale: () => {}, onOpenSettings: () => {} }

test('playlist failure notification shows durable counts in both languages', () => {
  const notifications = [
    { id: 'playlist', title: 'Album', error: { code: 'unknown' as const, detail: 'playlist_summary:2:1' } },
    { id: 'disk-full', title: 'Album', error: { code: 'disk_full' as const, detail: 'playlist_summary:1:1' } },
  ]
  const view = render(<NotificationCard locale="en" notifications={notifications} />)
  const english = screen.getAllByRole('alert')
  expect(english[0].textContent).toContain('2 correct, 1 failed')
  expect(english[1].textContent).toContain('Not enough storage space. 1 correct, 1 failed')
  view.rerender(<NotificationCard locale="es" notifications={notifications} />)
  const spanish = screen.getAllByRole('alert')
  expect(spanish[0].textContent).toContain('2 correctos, 1 fallidos')
  expect(spanish[1].textContent).toContain('No hay suficiente espacio de almacenamiento. 1 correctos, 1 fallidos')
  view.unmount()
})

test('terminal failure stays announced after queue removal, UI recreation, and mock transport restart', async () => {
  const storage = createMemoryMockStorage()
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ storage, clock, outcomes: { [analysisUrls.single]: 'failed' } })
  const id = await transport.call('enqueue_download', { request })
  clock.advanceBy(8000)
  expect(await transport.call('get_queue', {})).toEqual([])

  const firstStore = createDownloadFlowStore(transport)
  const first = render(<AppView {...viewProps} locale="en" flowStore={firstStore} />)
  const notification = await screen.findByRole('region', { name: 'Download errors' })
  await waitFor(() => expect(within(notification).getByRole('alert').textContent).toContain('Something went wrong.'))
  expect(notification.classList.contains('notification-toast')).toBe(true)
  expect(screen.getByRole('main').contains(notification)).toBe(false)
  expect(firstStore.getState().notifications.map((note) => note.id)).toEqual([id])
  first.rerender(<AppView {...viewProps} locale="es" flowStore={firstStore} />)
  expect(screen.getByRole('region', { name: 'Errores de descarga' }).textContent).toContain('Ocurrió un error.')
  first.rerender(<AppView {...viewProps} page="settings" locale="es" flowStore={firstStore} />)
  expect(screen.getByRole('region', { name: 'Errores de descarga' })).not.toBeNull()
  first.unmount()

  const recreated = render(<AppView {...viewProps} locale="es" flowStore={firstStore} />)
  await waitFor(() => expect(screen.getByRole('region', { name: 'Errores de descarga' }).getAttribute('tabindex')).toBe('-1'))
  expect(within(screen.getByRole('region', { name: 'Errores de descarga' })).getByRole('alert').textContent).toContain('Ocurrió un error.')
  recreated.unmount()

  const restarted = createSimulatorTransport({ storage, clock: createManualSimulatorClock() })
  const secondStore = createDownloadFlowStore(restarted)
  const second = render(<AppView {...viewProps} locale="en" flowStore={secondStore} />)
  await waitFor(() => expect(secondStore.getState().notifications.map((note) => note.id)).toEqual([id]))
  expect(within(screen.getByRole('region', { name: 'Download errors' })).getByRole('alert').textContent).toContain('Something went wrong.')
  second.unmount()
})

test('dismissal waits for success, preserves a failed notification, and restores focus after removal', async () => {
  const storage = createMemoryMockStorage()
  const seedClock = createManualSimulatorClock()
  const seed = createSimulatorTransport({ storage, clock: seedClock, outcomes: { [analysisUrls.single]: 'failed' } })
  const id = await seed.call('enqueue_download', { request })
  seedClock.advanceBy(8000)
  const snapshot = storage.load()!
  snapshot.notifications[0].error = { code: 'disk_full', detail: 'Raw engine output' }
  storage.save(snapshot)

  const simulator = createSimulatorTransport({ storage, clock: createManualSimulatorClock() })
  const originalCall = simulator.call.bind(simulator)
  let rejectFirst!: (reason: unknown) => void
  let resolveSuccess!: () => void
  let firstAttempt = true
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => {
      if (command === 'dismiss_error_notification' && firstAttempt) {
        firstAttempt = false
        return new Promise<void>((_resolve, reject) => { rejectFirst = reject })
      }
      if (command === 'dismiss_error_notification') {
        return originalCall(command, args).then(() => new Promise<void>((resolve) => { resolveSuccess = resolve }))
      }
      return originalCall(command, args)
    }) as AppTransport['call'],
  }
  const flowStore = createDownloadFlowStore(transport)
  const view = render(<AppView {...viewProps} locale="en" flowStore={flowStore} />)
  const card = await screen.findByRole('region', { name: 'Download errors' })
  await waitFor(() => expect(within(card).getByRole('alert').textContent).toContain('Not enough storage space.'))
  expect(card.textContent).not.toContain('Raw engine output')
  const dismiss = within(card).getByRole('button', { name: /Dismiss error for/ })
  await userEvent.setup().click(dismiss)
  await waitFor(() => expect(dismiss.hasAttribute('disabled')).toBe(true))
  expect(within(card).getByRole('alert')).not.toBeNull()
  rejectFirst({ code: 'permission_denied', detail: null })
  await waitFor(() => expect(dismiss.hasAttribute('disabled')).toBe(false))
  expect(within(card).getByRole('alert')).not.toBeNull()
  expect(document.activeElement).toBe(dismiss)
  expect(await simulator.call('get_error_notifications', {})).toHaveLength(1)

  await userEvent.setup().click(dismiss)
  await waitFor(() => expect(resolveSuccess).toBeDefined())
  await waitFor(async () => expect(await simulator.call('get_error_notifications', {})).toEqual([]))
  expect(within(card).getByRole('alert')).not.toBeNull()
  resolveSuccess()
  await waitFor(() => expect(screen.queryByRole('region', { name: 'Download errors' })).toBeNull())
  expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(await simulator.call('get_error_notifications', {})).toEqual([])
  expect(flowStore.getState().notifications).toEqual([])
  expect(id).toBeTruthy()
  view.unmount()
})
