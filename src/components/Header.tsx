// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { t } from '../i18n'
import type { Locale } from '../i18n'
import { useShellStore } from '../state/shell'
import { IconButton } from './ui/Button'

function Logo() {
  return (
    <svg aria-hidden="true" className="h-7 w-7 shrink-0 text-primary" viewBox="0 0 32 32" fill="none">
      <path d="M5 6h19L8 26h19M17 6l8 20M7 19h11" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function GlobeIcon() {
  return (
    <svg aria-hidden="true" className="h-6 w-6" viewBox="0 0 24 24" fill="none">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.8" />
      <path d="M3 12h18M12 3c2.5 2.5 3.7 5.5 3.7 9s-1.2 6.5-3.7 9c-2.5-2.5-3.7-5.5-3.7-9S9.5 5.5 12 3Z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
    </svg>
  )
}

function SettingsIcon() {
  return (
    <svg aria-hidden="true" className="h-6 w-6" viewBox="0 0 24 24" fill="none">
      <path d="M10 3.5h4l.5 2.1c.5.2 1 .5 1.5.9l2.1-.6 2 3.5-1.6 1.5a7 7 0 0 1 0 1.8l1.6 1.5-2 3.5-2.1-.6c-.5.4-1 .7-1.5.9L14 20.5h-4L9.5 18c-.5-.2-1-.5-1.5-.9l-2.1.6-2-3.5 1.6-1.5a7 7 0 0 1 0-1.8L3.9 9.4l2-3.5 2.1.6c.5-.4 1-.7 1.5-.9L10 3.5Z" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      <circle cx="12" cy="12" r="2.5" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  )
}

interface HeaderViewProps {
  locale: Locale
  onToggleLocale: () => void
  onOpenSettings: () => void
}

export function HeaderView({ locale, onToggleLocale, onOpenSettings }: HeaderViewProps) {
  return (
    <header className="sticky top-0 z-10 flex min-h-16 items-center justify-between gap-stack border-b border-border bg-canvas px-section md:min-h-[5.375rem] md:px-shell">
      <div className="flex min-w-0 items-center gap-control-gap">
        <Logo />
        <span className="truncate text-app-title font-semibold text-text-strong">{t(locale, 'app.name')}</span>
      </div>
      <div className="flex shrink-0 items-center gap-compact">
        <button
          type="button"
          aria-label={t(locale, locale === 'en' ? 'header.switchToSpanish' : 'header.switchToEnglish')}
          className="inline-flex min-h-11 min-w-11 items-center justify-center gap-compact rounded-control px-control-gap text-text focus-visible:outline-2 focus-visible:outline-offset-2"
          onClick={onToggleLocale}
        >
          <GlobeIcon />
          <span aria-hidden="true" className="text-small font-medium">{locale.toUpperCase()}</span>
        </button>
        <IconButton
          label={t(locale, 'header.settings')}
          icon={<SettingsIcon />}
          onClick={onOpenSettings}
          className="rounded-control text-text"
        />
      </div>
    </header>
  )
}

export function Header() {
  const locale = useShellStore((state) => state.locale)
  const toggleLocale = useShellStore((state) => state.toggleLocale)
  const openSettings = useShellStore((state) => state.openSettings)

  return <HeaderView locale={locale} onToggleLocale={toggleLocale} onOpenSettings={openSettings} />
}
