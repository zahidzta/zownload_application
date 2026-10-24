// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { expect, test, vi } from 'vitest'
import { AppView } from '../../src/App'
import type { Locale } from '../../src/i18n'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { createMemoryMockStorage } from '../../src/transport/mockStorage'
import { createSimulatorTransport } from '../../src/transport/simulator'

test('Settings choices persist, picker cancellation leaves the path alone, and language changes immediately', async () => {
  const storage = createMemoryMockStorage()
  const transport = createSimulatorTransport({ storage })
  const store = createDownloadFlowStore(transport)
  const pickFolder = vi.fn<() => Promise<string | null>>()
    .mockResolvedValueOnce(null).mockResolvedValueOnce('C:/Media/Zownload')
  function View() {
    const [locale, setLocale] = useState<Locale>('en')
    return <AppView locale={locale} page="settings" flowStore={store}
      onBack={() => {}} onOpenSettings={() => {}} onToggleLocale={() => {
        const language = locale === 'en' ? 'es' : 'en'
        setLocale(language)
        void store.getState().saveSettings({ language })
      }}
      pickFolder={pickFolder} />
  }
  const user = userEvent.setup()
  const view = render(<View />)
  const back = screen.getByRole('button', { name: 'Back to downloads' })
  expect(document.activeElement).toBe(back)
  await waitFor(() => expect(screen.getByRole('combobox', { name: 'Language' }).hasAttribute('disabled')).toBe(false))

  await user.click(screen.getByRole('button', { name: 'Choose folder' }))
  await waitFor(() => expect(pickFolder).toHaveBeenCalledTimes(1))
  expect(store.getState().settings?.downloadDir).toBeNull()
  await user.click(screen.getByRole('button', { name: 'Choose folder' }))
  await waitFor(() => expect(store.getState().settings?.downloadDir).toBe('C:/Media/Zownload'))
  expect(screen.getByText('C:/Media/Zownload')).toBeTruthy()

  await user.click(screen.getByRole('checkbox', { name: 'Download a playlist as a .zip file' }))
  await user.selectOptions(screen.getByRole('combobox', { name: 'Language' }), 'es')
  expect(screen.getByRole('heading', { name: 'Configuración', level: 2 })).toBeTruthy()
  await waitFor(async () => expect(await transport.call('get_settings', {})).toEqual({
    language: 'es', zipPlaylists: true, downloadDir: 'C:/Media/Zownload',
  }))
  view.unmount()

  const restarted = createSimulatorTransport({ storage })
  expect(await restarted.call('get_settings', {})).toEqual({
    language: 'es', zipPlaylists: true, downloadDir: 'C:/Media/Zownload',
  })
})

test('Android hides folder selection and engine update remains separate from app updates', async () => {
  const userAgent = vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue('Mozilla/5.0 (Linux; Android 15)')
  const store = createDownloadFlowStore(createSimulatorTransport())
  render(<AppView locale="en" page="settings" flowStore={store}
    onBack={() => {}} onOpenSettings={() => {}} onToggleLocale={() => {}} />)
  expect(screen.queryByRole('button', { name: 'Choose folder' })).toBeNull()
  expect(screen.queryByText('Download folder')).toBeNull()
  await userEvent.setup().click(screen.getByRole('button', { name: 'Check engine update' }))
  await waitFor(() => expect(screen.getByRole('status').textContent).toContain('Engine update available:'))
  await userEvent.setup().click(screen.getByRole('button', { name: 'Update engine' }))
  await waitFor(() => expect(screen.getByRole('status').textContent).toContain('Engine is current:'))
  expect(screen.getByRole('heading', { name: 'Zownload updates' })).toBeTruthy()
  expect(screen.queryByRole('button', { name: 'Update Zownload' })).toBeNull()
  userAgent.mockRestore()
})
