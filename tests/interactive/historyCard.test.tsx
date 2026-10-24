// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test, vi } from 'vitest'
import { AppView } from '../../src/App'
import { HistoryCard } from '../../src/components/HistoryCard'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'
import type { HistoryEntry } from '../../shared/contract'

test('History redownload queues its stored request directly, then per-row delete and clear persist', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const singleRequest = { url: analysisUrls.single, format: 'mp3' as const,
    quality: { type: 'audio' as const, bitrate: 128 }, isPlaylist: false }
  const playlistRequest = { url: analysisUrls.playlist, format: 'mp4' as const,
    quality: { type: 'min' as const }, isPlaylist: true }
  await transport.call('enqueue_download', { request: singleRequest })
  await transport.call('enqueue_download', { request: playlistRequest })
  clock.advanceBy(8000)
  expect(await transport.call('get_history', {})).toHaveLength(2)
  const flowStore = createDownloadFlowStore(transport)
  const props = { onBack: () => {}, onToggleLocale: () => {}, onOpenSettings: () => {}, flowStore }
  const view = render(<AppView {...props} locale="en" page="main" />)
  const history = await screen.findByRole('region', { name: 'History' })
  await waitFor(() => expect(within(history).getAllByRole('listitem')).toHaveLength(2))
  const user = userEvent.setup()
  const newest = within(history).getAllByRole('listitem')[0]
  within(newest).getByRole('button', { name: 'Redownload' }).focus()
  await user.keyboard('{Enter}')
  await waitFor(() => expect(flowStore.getState().queueItems).toHaveLength(1))
  expect(flowStore.getState().queueItems[0].request).toEqual(playlistRequest)
  expect(flowStore.getState().step).toBe('input')
  expect(screen.getByRole('textbox', { name: 'Enter URL' })).not.toBeNull()

  view.rerender(<AppView {...props} locale="es" page="settings" />)
  expect(screen.getAllByRole('heading', { name: 'Configuración' }).length).toBeGreaterThan(0)
  view.rerender(<AppView {...props} locale="es" page="main" />)
  const historial = screen.getByRole('region', { name: 'Historial' })
  expect(within(historial).getAllByRole('listitem')).toHaveLength(2)
  await user.click(within(historial).getAllByRole('button', { name: /Eliminar del historial/ })[0])
  await waitFor(() => expect(within(historial).getAllByRole('listitem')).toHaveLength(1))
  expect(document.activeElement).toBe(historial)
  expect(await transport.call('get_history', {})).toHaveLength(1)
  await user.click(within(historial).getByRole('button', { name: 'Borrar historial' }))
  await waitFor(() => expect(within(historial).getByText('Aún no hay historial')).not.toBeNull())
  expect(document.activeElement).toBe(historial)
  expect(await transport.call('get_history', {})).toEqual([])
  view.unmount()
})

test('duplicate titles keep separate history rows identified by id', async () => {
  const request = { url: analysisUrls.single, format: 'mp3' as const,
    quality: { type: 'audio' as const, bitrate: 128 }, isPlaylist: false }
  const entries: HistoryEntry[] = [
    { id: 11, title: 'Same title', request },
    { id: 10, title: 'Same title', request: { ...request, url: analysisUrls.playlist, isPlaylist: true, quality: { type: 'max' } } },
  ]
  const onDelete = vi.fn()
  const view = render(<HistoryCard locale="en" entries={entries} onDelete={onDelete} onRedownload={() => {}} onClear={() => {}} />)
  const rows = screen.getAllByRole('listitem')
  expect(rows).toHaveLength(2)
  await userEvent.setup().click(within(rows[1]).getByRole('button', { name: 'Delete from history: Same title' }))
  expect(onDelete).toHaveBeenCalledWith(10)
  view.rerender(<HistoryCard locale="en" entries={entries.slice(0, 1)} onDelete={onDelete} onRedownload={() => {}} onClear={() => {}} />)
  expect(screen.getAllByRole('listitem')).toHaveLength(1)
  expect(screen.getByText('MP3')).not.toBeNull()
})
