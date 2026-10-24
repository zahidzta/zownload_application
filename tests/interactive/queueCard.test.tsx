// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { act, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { AppView } from '../../src/App'
import { QueueCard } from '../../src/components/QueueCard'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'
import type { QueueItem } from '../../shared/contract'

const singleRequest = {
  url: analysisUrls.single, format: 'mp3' as const,
  quality: { type: 'audio' as const, bitrate: 128 }, isPlaylist: false,
}

test('single queue progress has an accessible value and keyboard Stop, Continue, Cancel actions', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const flowStore = createDownloadFlowStore(transport)
  const view = render(<AppView locale="en" page="main" onBack={() => {}} onToggleLocale={() => {}}
    onOpenSettings={() => {}} flowStore={flowStore} />)
  await waitFor(() => expect(flowStore.getState().settings).not.toBeNull())
  const id = await transport.call('enqueue_download', { request: singleRequest })
  act(() => clock.advanceBy(2000))
  expect(screen.getByRole('progressbar', { name: /Download progress for/ }).getAttribute('aria-valuenow')).toBe('25')
  expect(screen.getByText('25%')).not.toBeNull()
  const user = userEvent.setup()
  screen.getByRole('button', { name: 'Stop' }).focus()
  await user.keyboard('{Enter}')
  act(() => clock.advanceBy(0))
  expect(screen.getByText('Paused')).not.toBeNull()
  expect(screen.queryByRole('progressbar')).toBeNull()
  expect(screen.getByText('25%')).not.toBeNull()
  await user.click(screen.getByRole('button', { name: 'Continue' }))
  act(() => clock.advanceBy(0))
  expect(screen.getByText('Downloading')).not.toBeNull()
  await user.click(screen.getByRole('button', { name: 'Cancel' }))
  act(() => clock.advanceBy(0))
  await waitFor(() => expect(screen.getByText('No active downloads')).not.toBeNull())
  expect(document.activeElement?.getAttribute('aria-labelledby')).toBeTruthy()
  expect(await transport.call('get_queue', {})).toEqual([])
  expect(id).toMatch(/^[0-9a-f-]{36}$/)
  view.unmount()
})

test('playlist shows completed count, failures, and disabled Stop during processing and packaging', () => {
  const base: QueueItem = {
    id: 'one', request: { url: analysisUrls.playlist, format: 'mp4', quality: { type: 'max' }, isPlaylist: true },
    title: 'Playlist', thumbnail: null, error: null, status: 'downloading',
    progress: { kind: 'playlist', done: 10, failed: 5, total: 17, currentTitle: 'Next title', currentPercent: 82 },
  }
  const view = render(<QueueCard locale="en" items={[base]} onPause={() => {}} onCancel={() => {}} />)
  expect(screen.getByText('10/17')).not.toBeNull()
  expect(screen.getByText('10 correct, 5 failed')).not.toBeNull()
  expect(screen.getByRole('progressbar').getAttribute('aria-valuenow')).toBe('82')
  expect(screen.getByRole('button', { name: 'Stop' }).hasAttribute('disabled')).toBe(false)
  view.rerender(<QueueCard locale="es" items={[{ ...base, status: 'postProcessing' }]} onPause={() => {}} onCancel={() => {}} />)
  expect(screen.getByText('Procesando archivo')).not.toBeNull()
  expect(screen.getByText('10 correctos, 5 fallidos')).not.toBeNull()
  expect(screen.getByRole('button', { name: 'Detener' }).hasAttribute('disabled')).toBe(true)
  view.rerender(<QueueCard locale="es" items={[{ ...base, status: 'packaging' }]} onPause={() => {}} onCancel={() => {}} />)
  expect(screen.getByText('Empaquetando lista')).not.toBeNull()
  expect(within(screen.getByRole('region', { name: 'Cola' })).getByRole('button', { name: 'Cancelar' }).hasAttribute('disabled')).toBe(false)
})

test('a missed resume event clears the pending control when the UI reconnects', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const flow = createDownloadFlowStore(transport)
  const off = flow.getState().connectActivity()
  await waitFor(() => expect(flow.getState().settings).not.toBeNull())
  const id = await transport.call('enqueue_download', { request: singleRequest })
  clock.advanceBy(1000)
  await waitFor(() => expect(flow.getState().queueItems[0]?.status).toBe('downloading'))
  await flow.getState().pauseQueueItem(id)
  expect(flow.getState().queueItems[0].status).toBe('paused')
  off()
  await flow.getState().resumeQueueItem(id)
  expect(flow.getState().queueActionId).toBe(id)
  clock.advanceBy(0)
  const reconnect = flow.getState().connectActivity()
  await waitFor(() => expect(flow.getState().queueItems[0].status).toBe('downloading'))
  expect(flow.getState().queueActionId).toBeNull()
  reconnect()
})
