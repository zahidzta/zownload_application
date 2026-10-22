// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { AppShell } from './components/AppShell'
import { Card } from './components/ui/Card'
import { t } from './i18n'
import { useShellStore } from './state/shell'

export default function App() {
  const locale = useShellStore((state) => state.locale)

  return (
    <AppShell>
      <Card
        title={t(locale, 'input.title')}
        className="min-h-[21.3125rem] rounded-card border border-border bg-card p-card"
        headingClassName="text-card-title font-medium text-text-strong"
      />
    </AppShell>
  )
}
