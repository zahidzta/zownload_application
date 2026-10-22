// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { create } from 'zustand'
import type { Locale } from '../i18n'

export type ShellPage = 'main' | 'settings'

interface ShellState {
  locale: Locale
  page: ShellPage
  setLocale: (locale: Locale) => void
  toggleLocale: () => void
  openSettings: () => void
  closeSettings: () => void
}

// Settings controls and persistence are added in 1C; this store only owns shell navigation.
export const useShellStore = create<ShellState>()((set) => ({
  locale: 'en',
  page: 'main',
  setLocale: (locale) => set({ locale }),
  toggleLocale: () => set((state) => ({ locale: state.locale === 'en' ? 'es' : 'en' })),
  openSettings: () => set({ page: 'settings' }),
  closeSettings: () => set({ page: 'main' }),
}))
