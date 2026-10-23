// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useEffect, useRef } from 'react'
import type { Locale } from '../i18n'
import { t } from '../i18n'
import { Button } from './ui/Button'
import { Card } from './ui/Card'
import { Page } from './ui/Page'

interface SettingsShellProps {
  locale: Locale
  onBack: () => void
}

export function SettingsShell({ locale, onBack }: SettingsShellProps) {
  const backButton = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    backButton.current?.focus()
  }, [])

  return (
    <Page
      title={t(locale, 'settings.title')}
      headingClassName="sr-only"
      className="mx-auto w-full max-w-[86.25rem] px-shell-inline pt-card pb-shell lg:pt-shell xl:px-0"
    >
      <Card
        title={t(locale, 'settings.title')}
        className="w-full max-w-[42rem] rounded-card border border-border bg-card p-4 lg:p-card"
        headingClassName="text-card-title font-medium text-text-strong"
      >
        <Button
          ref={backButton}
          label={t(locale, 'navigation.back')}
          onClick={onBack}
          className="mt-section rounded-control px-stack text-accent-text"
        />
      </Card>
    </Page>
  )
}
