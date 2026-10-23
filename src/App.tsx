// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { AppShellView } from './components/AppShell'
import { HeaderView } from './components/Header'
import { SettingsShell } from './components/SettingsShell'
import { Card } from './components/ui/Card'
import { t } from './i18n'
import type { Locale } from './i18n'
import { useShellStore } from './state/shell'
import type { ShellPage } from './state/shell'

interface AppViewProps {
  locale: Locale
  page: ShellPage
  onBack: () => void
  onToggleLocale: () => void
  onOpenSettings: () => void
}

export function AppView({ locale, page, onBack, onToggleLocale, onOpenSettings }: AppViewProps) {
  return (
    <>
      <HeaderView locale={locale} onToggleLocale={onToggleLocale} onOpenSettings={onOpenSettings} />
      <div hidden={page !== 'main'}>
        <AppShellView locale={locale}>
          <Card
            title={t(locale, 'input.title')}
            className="min-h-[21.3125rem] rounded-card border border-border bg-card p-card"
            headingClassName="text-card-title font-medium text-text-strong"
          />
        </AppShellView>
      </div>
      {page === 'settings' && <SettingsShell locale={locale} onBack={onBack} />}
    </>
  )
}

export default function App() {
  const locale = useShellStore((state) => state.locale)
  const page = useShellStore((state) => state.page)
  const closeSettings = useShellStore((state) => state.closeSettings)
  const toggleLocale = useShellStore((state) => state.toggleLocale)
  const openSettings = useShellStore((state) => state.openSettings)

  function returnToMain() {
    closeSettings()
    // The header stays mounted while Settings is open, so focus can return to its trigger.
    document.querySelector<HTMLButtonElement>('header button:last-of-type')?.focus()
  }

  return (
    <AppView
      locale={locale}
      page={page}
      onBack={returnToMain}
      onToggleLocale={toggleLocale}
      onOpenSettings={openSettings}
    />
  )
}
