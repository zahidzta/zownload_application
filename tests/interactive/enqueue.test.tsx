// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useState } from 'react'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import { AppView } from '../../src/App'
import type { DownloadFlowStore } from '../../src/components/InputCard'
import type { Locale } from '../../src/i18n'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import type { ShellPage } from '../../src/state/shell'
import { analysisUrls } from '../../src/transport/fixtures'
import { createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'

function TestApp({ flowStore }: { flowStore: DownloadFlowStore }) {
  const [locale, setLocale] = useState<Locale>('en')
  const [page, setPage] = useState<ShellPage>('main')
  return <AppView locale={locale} page={page} onBack={() => setPage('main')}
    onOpenSettings={() => setPage('settings')}
    onToggleLocale={() => setLocale((current) => current === 'en' ? 'es' : 'en')} flowStore={flowStore} />
}

async function analyze(user: ReturnType<typeof userEvent.setup>, url: string, format: 'mp3' | 'mp4') {
  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), url)
  if (format === 'mp4') await user.click(screen.getByRole('radio', { name: 'MP4 (Video)' }))
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  await screen.findByRole('button', { name: 'Download' })
}

test('accepted single request uses the exact audio quality, clears Input, and shows a real queued snapshot', async () => {
  const user = userEvent.setup()
  const transport = createSimulatorTransport()
  const flowStore = createDownloadFlowStore(transport)
  render(<TestApp flowStore={flowStore} />)
  await analyze(user, analysisUrls.single, 'mp3')
  await user.selectOptions(screen.getByRole('combobox', { name: /Quality.*Requested maximum/ }), '192')
  await user.click(screen.getByRole('button', { name: 'Download' }))

  const input = await screen.findByRole('textbox', { name: 'Enter URL' }) as HTMLInputElement
  expect(input.value).toBe('')
  const snapshot = (await transport.call('get_queue', {}))[0]
  expect(snapshot.request).toEqual({
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 192 }, isPlaylist: false,
  })
  await waitFor(() => expect(flowStore.getState().queueItems).toHaveLength(1))
  expect(flowStore.getState().queueItems).toEqual([snapshot])
  const queue = screen.getByRole('region', { name: 'Queue' })
  expect(within(queue).getByText('10號風...')).toBeTruthy()
  expect(within(queue).getByText('Queued')).toBeTruthy()
  expect(within(queue).queryByText('No active downloads')).toBeNull()
  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(within(screen.getByRole('region', { name: 'Cola' })).getByText('En cola')).toBeTruthy()
})

test('playlist MP4 Min request reaches the queue and Settings restores the selected preview', async () => {
  const user = userEvent.setup()
  const transport = createSimulatorTransport()
  const flowStore = createDownloadFlowStore(transport)
  render(<TestApp flowStore={flowStore} />)
  await analyze(user, analysisUrls.playlist, 'mp4')
  const quality = screen.getByRole('combobox', { name: 'Quality' }) as HTMLSelectElement
  await user.selectOptions(quality, 'min')
  await user.click(screen.getByRole('button', { name: 'Settings' }))
  expect(screen.getByRole('button', { name: 'Back to downloads' })).toBeTruthy()
  await user.click(screen.getByRole('button', { name: 'Back to downloads' }))
  expect(screen.getByRole('combobox', { name: 'Quality' })).toBe(quality)
  expect(quality.value).toBe('min')
  await user.click(screen.getByRole('button', { name: 'Download' }))

  await screen.findByRole('textbox', { name: 'Enter URL' })
  expect((await transport.call('get_queue', {}))[0].request).toEqual({
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'min' }, isPlaylist: true,
  })
  expect(await within(screen.getByRole('region', { name: 'Queue' })).findByText('Official Blender Open Movies')).toBeTruthy()
})

test('a pending enqueue blocks duplicate clicks and clears Input as soon as acceptance arrives', async () => {
  const user = userEvent.setup()
  const simulator = createSimulatorTransport()
  const call = simulator.call.bind(simulator)
  let accept!: () => void
  const pending = new Promise<void>((resolve) => { accept = resolve })
  let enqueueCalls = 0
  const transport: AppTransport = {
    ...simulator,
    call: (async (command, args) => {
      if (command === 'enqueue_download') {
        enqueueCalls++
        await pending
      }
      return call(command, args)
    }) as AppTransport['call'],
  }
  const flowStore = createDownloadFlowStore(transport)
  render(<TestApp flowStore={flowStore} />)
  await analyze(user, analysisUrls.single, 'mp3')
  const button = screen.getByRole('button', { name: 'Download' }) as HTMLButtonElement
  await user.click(button)
  expect(button.disabled).toBe(true)
  await user.click(button)
  expect(enqueueCalls).toBe(1)
  accept()
  const input = await screen.findByRole('textbox', { name: 'Enter URL' }) as HTMLInputElement
  expect(input.value).toBe('')
  await waitFor(() => expect(flowStore.getState().queueItems).toHaveLength(1))
  expect(enqueueCalls).toBe(1)
})

test('typed enqueue rejection returns to Input with an announced error and no queue item', async () => {
  const user = userEvent.setup()
  const simulator = createSimulatorTransport()
  const call = simulator.call.bind(simulator)
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => command === 'enqueue_download'
      ? Promise.reject({ code: 'permission_denied', detail: 'Synthetic rejection' })
      : call(command, args)) as AppTransport['call'],
  }
  render(<TestApp flowStore={createDownloadFlowStore(transport)} />)
  await analyze(user, analysisUrls.single, 'mp3')
  await user.click(screen.getByRole('button', { name: 'Download' }))
  expect((await screen.findByRole('alert')).textContent).toBe('Storage permission denied.')
  expect((screen.getByRole('textbox', { name: 'Enter URL' }) as HTMLInputElement).value).toBe(analysisUrls.single)
  expect(await transport.call('get_queue', {})).toEqual([])
  expect(within(screen.getByRole('region', { name: 'Queue' })).getByText('No active downloads')).toBeTruthy()
})
