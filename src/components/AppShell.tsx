// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { ReactNode } from 'react'
import type { QueueItem } from '../../shared/contract'
import type { Locale } from '../i18n'
import { Header } from './Header'
import { Card } from './ui/Card'
import { Page } from './ui/Page'
import { t } from '../i18n'
import { useShellStore } from '../state/shell'
import { QueueCard } from './QueueCard'

interface AppShellProps {
  children: ReactNode
  queueItems?: QueueItem[]
  queueActionId?: string | null
  onPause?: (id: string) => void
  onResume?: (id: string) => void
  onCancel?: (id: string) => void
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

export function AppShellView({ locale, children, queueItems = [], queueActionId, onPause, onResume, onCancel }: AppShellProps & { locale: Locale }) {
  return (
    <Page
        title={t(locale, 'input.title')}
        headingClassName="sr-only"
        className="mx-auto grid w-full max-w-[86.25rem] grid-cols-1 gap-section px-shell-inline pt-card pb-shell lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] lg:gap-card lg:pt-shell xl:px-0"
      >
        <div className="app-shell-main min-w-0 lg:col-start-1">{children}</div>
        <div className="flex min-w-0 flex-col gap-stack lg:col-start-2 lg:gap-5">
          <QueueCard locale={locale} items={queueItems} busyId={queueActionId}
            onPause={onPause} onResume={onResume} onCancel={onCancel} />
          <Card
            title={t(locale, 'history.title')}
            className="rounded-card border border-border bg-card p-4 lg:min-h-[7.625rem] lg:p-5"
            headingClassName="text-card-title font-medium text-text"
          >
            <p className="mt-stack mb-0 text-body text-text lg:mt-section">{t(locale, 'history.empty')}</p>
          </Card>
        </div>
    </Page>
  )
}
