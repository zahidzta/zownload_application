// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useState } from 'react'
import { render, screen, within } from '@testing-library/react'
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
  return <AppView locale={locale} page="main" onBack={() => {}} onOpenSettings={() => {}}
    onToggleLocale={() => setLocale((current) => current === 'en' ? 'es' : 'en')} flowStore={flowStore} />
}

async function analyzePlaylist(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), analysisUrls.playlist)
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  return screen.findByRole('heading', { name: 'Official Blender Open Movies' })
}

test('playlist shows all 17 titles in a bounded keyboard scroll region and only Max/Min', async () => {
  const user = userEvent.setup()
  const flowStore = createDownloadFlowStore(createSimulatorTransport())
  render(<TestApp flowStore={flowStore} />)
  const heading = await analyzePlaylist(user)
  expect(heading.closest('section')?.getAttribute('aria-labelledby')).toBe(heading.id)
  expect(screen.getByText('Blender', { selector: 'p.mt-2' })).toBeTruthy()
  expect(screen.getByText('YouTube')).toBeTruthy()
  expect(screen.getByText('17', { selector: 'strong' })).toBeTruthy()
  expect(heading.closest('section')?.querySelector('img')?.getAttribute('src')).toBe('/fixtures/blender-playlist-cover.jpg')

  const region = screen.getByRole('region', { name: 'Items in list' })
  expect(region.className).toContain('max-h-[22rem]')
  const titles = within(region).getAllByRole('listitem')
  expect(titles).toHaveLength(17)
  expect(titles[0].textContent).toContain('SINGULARITY')
  expect(titles[16].textContent).toContain('Elephants Dream')
  await user.tab()
  region.focus()
  expect(document.activeElement).toBe(region)

  const quality = screen.getByRole('combobox', { name: 'Quality' }) as HTMLSelectElement
  expect(Array.from(quality.options, (option) => option.value)).toEqual(['max', 'min'])
  await user.selectOptions(quality, 'min')
  expect(flowStore.getState().selectedQuality).toEqual({ type: 'min' })
  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(screen.getByRole('combobox', { name: 'Calidad' })).toBe(quality)
  expect(screen.getByRole('region', { name: 'Elementos de la lista' })).toBe(region)
  expect(quality.options[1].textContent).toBe('Calidad mínima')
  await user.click(screen.getByRole('button', { name: 'Volver' }))
  expect((screen.getByRole('textbox', { name: 'Introduce la URL' }) as HTMLInputElement).value).toBe(analysisUrls.playlist)
})

test('duplicate and long titles stay distinct and a null image has a translated fallback', async () => {
  const user = userEvent.setup()
  const original = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.playlist })
  if (original.kind !== 'playlist') throw new Error('Expected playlist result')
  const longTitle = 'A very long playlist title '.repeat(12)
  const result: AnalyzeResult = { ...original, thumbnail: null, itemTitles: [longTitle, longTitle, ...original.itemTitles] }
  const simulator = createSimulatorTransport()
  const call = simulator.call.bind(simulator)
  const transport: AppTransport = {
    ...simulator,
    call: ((command, args) => command === 'analyze_url' ? Promise.resolve(result) : call(command, args)) as AppTransport['call'],
  }
  render(<TestApp flowStore={createDownloadFlowStore(transport)} />)
  await analyzePlaylist(user)
  expect(screen.getByRole('img', { name: 'Thumbnail unavailable' })).toBeTruthy()
  const region = screen.getByRole('region', { name: 'Items in list' })
  const items = within(region).getAllByRole('listitem')
  expect(items).toHaveLength(19)
  expect(items[0].textContent).toBe(longTitle)
  expect(items[1].textContent).toBe(longTitle)
  expect(items[0].className).toContain('wrap-break-word')
  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(screen.getByRole('img', { name: 'Miniatura no disponible' })).toBeTruthy()
})
