// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useState } from 'react'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { expect, test } from 'vitest'
import type { AnalyzeResult } from '../../shared/contract'
import App, { AppView } from '../../src/App'
import type { DownloadFlowStore } from '../../src/components/InputCard'
import type { Locale } from '../../src/i18n'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { useShellStore } from '../../src/state/shell'
import { analysisUrls } from '../../src/transport/fixtures'
import { createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'

function TestApp({ flowStore }: { flowStore: DownloadFlowStore }) {
  const [locale, setLocale] = useState<Locale>('en')
  return (
    <AppView
      locale={locale}
      page="main"
      onBack={() => {}}
      onOpenSettings={() => {}}
      onToggleLocale={() => setLocale((current) => current === 'en' ? 'es' : 'en')}
      flowStore={flowStore}
    />
  )
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise
    reject = rejectPromise
  })
  return { promise, resolve, reject }
}

test('Input has keyboard-accessible format choices and Enter submits the URL', async () => {
  const user = userEvent.setup()
  const flowStore = createDownloadFlowStore(createSimulatorTransport())
  render(<TestApp flowStore={flowStore} />)

  const url = screen.getByRole('textbox', { name: 'Enter URL' })
  const mp3 = screen.getByRole('radio', { name: 'MP3 (Audio)' }) as HTMLInputElement
  const mp4 = screen.getByRole('radio', { name: 'MP4 (Video)' }) as HTMLInputElement
  expect(mp3.checked).toBe(true)
  await user.click(url)
  await user.tab()
  expect(document.activeElement).toBe(mp3)
  await user.click(mp4)
  expect(mp4.checked).toBe(true)
  await user.tab()
  await user.tab({ shift: true })
  expect(document.activeElement).toBe(mp4)
  await user.type(url, analysisUrls.single)
  await user.keyboard('{Enter}')

  await waitFor(() => expect(flowStore.getState().step).toBe('download'))
  expect(flowStore.getState().format).toBe('mp4')
  expect(screen.queryByRole('textbox', { name: 'Enter URL' })).toBeNull()
})

test('analyzing blocks duplicate submission and translated errors stay below the URL', async () => {
  const user = userEvent.setup()
  const pending = deferred<AnalyzeResult>()
  const simulator = createSimulatorTransport()
  let analyzeCalls = 0
  const transport: AppTransport = {
    ...simulator,
    call: ((command: string, args: unknown) => {
      if (command === 'analyze_url') {
        analyzeCalls++
        return pending.promise
      }
      return simulator.call(command as 'get_queue', args as Record<string, never>)
    }) as AppTransport['call'],
  }
  const flowStore = createDownloadFlowStore(transport)
  render(<TestApp flowStore={flowStore} />)

  const url = screen.getByRole('textbox', { name: 'Enter URL' })
  await user.type(url, 'not-a-url')
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  const analyzing = screen.getByRole('button', { name: 'Analyzing' }) as HTMLButtonElement
  expect(analyzing.disabled).toBe(true)
  expect(analyzing.querySelector('.animate-spin')).not.toBeNull()
  await user.click(analyzing)
  expect(analyzeCalls).toBe(1)

  pending.reject({ code: 'invalid_url', detail: 'synthetic test error' })
  const error = await screen.findByRole('alert')
  expect(error.textContent).toBe('Enter a valid URL.')
  expect(error.previousElementSibling).toBe(url)
  expect(url.getAttribute('aria-describedby')).toBe(error.id)
  expect(url.getAttribute('aria-invalid')).toBe('true')
  expect(flowStore.getState().step).toBe('input')

  await user.click(screen.getByRole('button', { name: 'Switch to Spanish' }))
  expect(screen.getByRole('alert').textContent).toBe('Introduce una URL válida.')
  expect(screen.getByRole('textbox', { name: 'Introduce la URL' })).toBe(url)
  expect(screen.getByRole('button', { name: 'Convertir' })).toBeTruthy()
})

test('unsupported URLs report their type in Input and an edit clears the error', async () => {
  const user = userEvent.setup()
  const flowStore = createDownloadFlowStore(createSimulatorTransport())
  render(<TestApp flowStore={flowStore} />)

  const url = screen.getByRole('textbox', { name: 'Enter URL' })
  await user.type(url, 'https://example.invalid/video')
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  expect((await screen.findByRole('alert')).textContent).toBe('This site is not supported.')
  await user.type(url, '/changed')
  expect(screen.queryByRole('alert')).toBeNull()
  expect(url.getAttribute('aria-invalid')).toBeNull()
})

test('the running mock keeps its loading state visible before showing an error', async () => {
  const user = userEvent.setup()
  useShellStore.setState({ locale: 'en', page: 'main' })
  render(<App />)

  await user.type(screen.getByRole('textbox', { name: 'Enter URL' }), 'bad-url')
  await user.click(screen.getByRole('button', { name: 'Convert' }))
  expect((screen.getByRole('button', { name: 'Analyzing' }) as HTMLButtonElement).disabled).toBe(true)
  expect((await screen.findByRole('alert')).textContent).toBe('Enter a valid URL.')
})
