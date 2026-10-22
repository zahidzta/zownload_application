// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { ReactNode } from 'react'
import type { Locale } from '../i18n'
import { Header } from './Header'
import { Card } from './ui/Card'
import { Page } from './ui/Page'
import { t } from '../i18n'
import { useShellStore } from '../state/shell'

interface AppShellProps {
  children: ReactNode
}

export function AppShell({ children }: AppShellProps) {
  const locale = useShellStore((state) => state.locale)

  return (
    <>
      <Header />
      <AppShellView locale={locale}>{children}</AppShellView>
    </>
  )
}

export function AppShellView({ locale, children }: AppShellProps & { locale: Locale }) {
  return (
    <Page
        title={t(locale, 'input.title')}
        headingClassName="sr-only"
        className="mx-auto grid w-full max-w-[86.25rem] grid-cols-1 gap-card px-section pt-shell lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] xl:px-0"
      >
        <div className="min-w-0 lg:col-start-1">{children}</div>
        <div className="flex min-w-0 flex-col gap-5 lg:col-start-2">
          <Card
            title={t(locale, 'queue.title')}
            className="min-h-[6.375rem] rounded-card border border-border bg-card p-5"
            headingClassName="text-card-title font-medium text-text"
          >
            <p className="mt-2 mb-0 text-body text-text">{t(locale, 'queue.empty')}</p>
          </Card>
          <Card
            title={t(locale, 'history.title')}
            className="min-h-[7.625rem] rounded-card border border-border bg-card p-5"
            headingClassName="text-card-title font-medium text-text"
          >
            <p className="mt-section mb-0 text-body text-text">{t(locale, 'history.empty')}</p>
          </Card>
        </div>
    </Page>
  )
}
