// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, expect, test } from 'vitest'
import { Header } from '../../src/components/Header'
import { useShellStore } from '../../src/state/shell'

beforeEach(() => useShellStore.setState({ locale: 'en', page: 'main' }))

test('language button switches the mounted header with keyboard and pointer input', async () => {
  const user = userEvent.setup()
  render(<Header />)

  const switchToSpanish = screen.getByRole('button', { name: 'Switch to Spanish' })
  expect(screen.getByText('EN')).toBeTruthy()

  await user.tab()
  expect(document.activeElement).toBe(switchToSpanish)
  await user.keyboard('{Enter}')

  const switchToEnglish = screen.getByRole('button', { name: 'Cambiar a inglés' })
  expect(screen.getByText('ES')).toBeTruthy()
  expect(screen.getByRole('button', { name: 'Configuración' })).toBeTruthy()

  await user.click(switchToEnglish)
  expect(screen.getByRole('button', { name: 'Switch to Spanish' })).toBeTruthy()
  expect(screen.getByText('EN')).toBeTruthy()
})
