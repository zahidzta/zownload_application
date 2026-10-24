// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useEffect, useRef } from 'react'
import type { HistoryEntry } from '../../shared/contract'
import type { Locale } from '../i18n'
import { t } from '../i18n'
import { Button, IconButton } from './ui/Button'
import { Card } from './ui/Card'

interface HistoryCardProps {
  locale: Locale
  entries: HistoryEntry[]
  busyId?: number | 'clear' | null
  onRedownload?: (id: number) => void
  onDelete?: (id: number) => void
  onClear?: () => void
}

function TrashIcon() {
  return (
    <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" focusable="false" aria-hidden="true">
      <path d="M4 7h16M9 7V4h6v3m3 0-1 13H7L6 7m4 4v6m4-6v6" />
    </svg>
  )
}

export function HistoryCard({ locale, entries, busyId = null, onRedownload, onDelete, onClear }: HistoryCardProps) {
  const cardRef = useRef<HTMLElement>(null)
  const removedId = useRef<number | 'clear' | null>(null)
  useEffect(() => {
    if (removedId.current === 'clear' && entries.length === 0 ||
        typeof removedId.current === 'number' && !entries.some((entry) => entry.id === removedId.current)) {
      cardRef.current?.focus()
      removedId.current = null
    }
  }, [entries])

  return (
    <Card ref={cardRef} title={t(locale, 'history.title')} tabIndex={-1}
      className="relative rounded-card border border-border bg-card p-4 lg:min-h-[7.625rem] lg:p-5"
      headingClassName="pr-11 text-card-title font-medium text-text">
      {entries.length > 0 && (
        <IconButton label={t(locale, 'history.clear')} icon={<TrashIcon />}
          onClick={() => { removedId.current = 'clear'; onClear?.() }}
          disabled={busyId !== null || !onClear}
          className="absolute top-2.5 right-2.5 text-text hover:text-text-strong lg:top-3 lg:right-3" />
      )}
      {entries.length === 0 ? (
        <p className="mt-stack mb-0 text-body text-text lg:mt-section">{t(locale, 'history.empty')}</p>
      ) : (
        <ul className="mt-4 mb-0 space-y-3 p-0">
          {entries.map((entry) => {
            const title = entry.title ?? entry.request.url
            return (
              <li key={entry.id} className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1 rounded-control border border-border px-3 py-2">
                <div className="min-w-0 flex-1">
                  <p className="m-0 wrap-break-word text-body text-text-strong">{title}</p>
                  <p className="m-0 text-small text-text">
                    {entry.request.isPlaylist ? t(locale, 'history.playlist') : entry.request.format.toUpperCase()}
                  </p>
                </div>
                <div className="flex items-center gap-1">
                  <Button label={t(locale, 'history.redownload')} onClick={() => onRedownload?.(entry.id)}
                    disabled={busyId !== null || !onRedownload} className="px-2 text-small text-accent-text" />
                  <IconButton label={t(locale, 'history.delete').replace('{title}', title)} icon={<TrashIcon />}
                    onClick={() => { removedId.current = entry.id; onDelete?.(entry.id) }}
                    disabled={busyId !== null || !onDelete} className="text-text hover:text-danger" />
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </Card>
  )
}
