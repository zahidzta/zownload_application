// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useState } from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import type { AnalyzeResult } from '../../shared/contract'
import { AppView } from '../../src/App'
import type { DownloadFlowStore } from '../../src/components/InputCard'
import type { Locale } from '../../src/i18n'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'

function TestApp({ flowStore }: { flowStore: DownloadFlowStore }) {
  const [locale, setLocale] = useState<Locale>('en')
  return <AppView
    locale={locale}
    page="main"
    onBack={() => {}}
    onOpenSettings={() => {}}
    onToggleLocale={() => setLocale((current) => current === 'en' ? 'es' : 'en')}
    flowStore={flowStore}
  />
}

function resultTransport(result: AnalyzeResult): AppTransport {
  const simulator = createSimulatorTransport()
  const call = simulator.call.bind(simulator)
  return {
    ...simulator,
    call: ((command, args) => command === 'analyze_url'
      ? Promise.resolve(result)
      : call(command, args)) as AppTransport['call'],
  }
}

test('single MP3 preview shows metadata, four requested maxima, and sends the selected quality', async () => {
  const user = userEvent.setup()
  const transport = createSimulatorTransport()
  const flowStore = createDownloadFlowStore(transport)
  render(<TestApp flowStore={flowStore} />)

  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), analysisUrls.single)
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  const title = await screen.findByRole('heading', { name: '10號風...' })
  expect(title.closest('section')?.getAttribute('aria-labelledby')).toBe(title.id)
  expect(screen.getByText('vgocyl')).toBeTruthy()
  expect(screen.getByLabelText('Duration: 0:15')).toBeTruthy()
  expect(screen.getByLabelText('Site: YouTube')).toBeTruthy()
  expect(title.closest('section')?.querySelector('img')?.getAttribute('src')).toMatch(/^data:image\/svg\+xml/)

  const quality = screen.getByRole('combobox', { name: /Quality.*Requested maximum/ }) as HTMLSelectElement
  expect(Array.from(quality.options, (option) => option.value)).toEqual(['320', '256', '192', '128'])
  expect(quality.value).toBe('320')
  expect(quality.textContent).not.toContain('~')
  await user.selectOptions(quality, '128')
  expect(flowStore.getState().selectedQuality).toEqual({ type: 'audio', bitrate: 128 })
  await user.click(screen.getByRole('button', { name: 'Download' }))

  await waitFor(() => expect(flowStore.getState().step).toBe('input'))
  expect((await transport.call('get_queue', {}))[0].request).toEqual({
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  })
  expect((screen.getByRole('textbox', { name: 'Enter URL' }) as HTMLInputElement).value).toBe('')
})

test('MP4 lists only offered heights, and Back restores the URL and chosen format', async () => {
  const user = userEvent.setup()
  const flowStore = createDownloadFlowStore(createSimulatorTransport())
  render(<TestApp flowStore={flowStore} />)

  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), analysisUrls.single)
  await user.click(screen.getByRole('radio', { name: 'MP4 (Video)' }))
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  const quality = await screen.findByRole('combobox', { name: 'Quality' }) as HTMLSelectElement
  expect(Array.from(quality.options, (option) => option.value)).toEqual(['720', '360', '144'])
  await user.selectOptions(quality, '360')
  expect(flowStore.getState().selectedQuality).toEqual({ type: 'video', height: 360 })

  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(screen.getByRole('combobox', { name: 'Calidad' })).toBe(quality)
  expect(screen.getByRole('button', { name: 'Descargar' })).toBeTruthy()
  await user.click(screen.getByRole('button', { name: 'Volver' }))
  expect((screen.getByRole('textbox', { name: 'Introduce la URL' }) as HTMLInputElement).value).toBe(analysisUrls.single)
  expect((screen.getByRole('radio', { name: 'MP4 (Video)' }) as HTMLInputElement).checked).toBe(true)
})

test('null thumbnail has a translated fallback and only matching engine estimates are shown', async () => {
  const user = userEvent.setup()
  const original = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.single })
  if (original.kind !== 'single') throw new Error('Expected single result')
  const result: AnalyzeResult = {
    ...original,
    thumbnail: null,
    estimates: [
      { format: 'mp3', quality: { type: 'audio', bitrate: 320 }, estimatedBytes: 8_800_000 },
      { format: 'mp4', quality: { type: 'video', height: 720 }, estimatedBytes: 12_300_000 },
    ],
  }
  const flowStore = createDownloadFlowStore(resultTransport(result))
  render(<TestApp flowStore={flowStore} />)

  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), analysisUrls.single)
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  expect(await screen.findByRole('img', { name: 'Thumbnail unavailable' })).toBeTruthy()
  const quality = screen.getByRole('combobox', { name: /Quality.*Requested maximum/ }) as HTMLSelectElement
  expect(quality.options[0].textContent).toContain('~8.8 MB')
  expect(quality.options[1].textContent).not.toContain('~')
  expect(quality.textContent).not.toContain('12.3')
  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(screen.getByRole('img', { name: 'Miniatura no disponible' })).toBeTruthy()
  expect(quality.options[0].textContent).toContain('~8,8 MB')
})
