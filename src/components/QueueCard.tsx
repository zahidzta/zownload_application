// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { QueueItem } from '../../shared/contract'
import type { Locale } from '../i18n'
import { t } from '../i18n'
import { Card } from './ui/Card'
import { Button } from './ui/Button'
import { useEffect, useRef } from 'react'

interface QueueCardProps {
  locale: Locale
  items: QueueItem[]
  busyId?: string | null
  onPause?: (id: string) => void
  onResume?: (id: string) => void
  onCancel?: (id: string) => void
}

function percent(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)))
}

function ProgressBar({ value, label }: { value: number; label: string }) {
  const current = percent(value)
  return (
    <div role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={current}
      className="queue-progress mt-2 h-2.5 overflow-hidden rounded-full bg-border">
      <div className="h-full rounded-full bg-primary" style={{ width: `${current}%` }} />
    </div>
  )
}

export function QueueCard({ locale, items, busyId = null, onPause, onResume, onCancel }: QueueCardProps) {
  const cardRef = useRef<HTMLElement>(null)
  const cancelledId = useRef<string | null>(null)
  useEffect(() => {
    if (cancelledId.current && !items.some((item) => item.id === cancelledId.current)) {
      cardRef.current?.focus()
      cancelledId.current = null
    }
  }, [items])
  return (
    <Card ref={cardRef} title={t(locale, 'queue.title')} tabIndex={-1}
      className="rounded-card border border-border bg-card p-4 lg:min-h-[6.375rem] lg:p-5"
      headingClassName="text-card-title font-medium text-text">
      {items.length === 0 ? <p className="mt-2 mb-0 text-body text-text">{t(locale, 'queue.empty')}</p> : (
        <ul className="mt-3 mb-0 space-y-4 p-0">
          {items.map((item) => {
            const title = item.title ?? item.request.url
            const paused = item.status === 'paused'
            const canPause = item.status === 'downloading'
            const canResume = paused
            const busy = busyId !== null
            const progress = item.progress
            const value = progress.kind === 'single' ? progress.percent : progress.currentPercent
            const statusKey = `queue.${item.status}` as const
            return (
              <li key={item.id} className="min-w-0 list-none border-t border-border pt-3 first:border-t-0 first:pt-0">
                <p className="m-0 min-w-0 wrap-break-word text-body font-medium text-text-strong">{title}</p>
                <div className="mt-1 flex min-w-0 flex-wrap items-baseline justify-between gap-x-2 text-small">
                  <span className={paused ? 'font-medium text-text-strong' : 'text-text'}>{t(locale, statusKey)}</span>
                  <span className="font-medium text-text-strong">
                    {progress.kind === 'single' ? `${percent(progress.percent)}%` : `${progress.done}/${progress.total}`}
                  </span>
                </div>
                {progress.kind === 'playlist' && progress.currentTitle && !paused && (
                  <p className="mt-1 mb-0 truncate text-small text-text-muted" title={progress.currentTitle}>{progress.currentTitle}</p>
                )}
                {progress.kind === 'playlist' && progress.failed > 0 && (
                  <p className="mt-1 mb-0 text-small text-text">
                    {t(locale, 'queue.failureSummary').replace('{done}', String(progress.done)).replace('{failed}', String(progress.failed))}
                  </p>
                )}
                {!paused && <ProgressBar value={value} label={t(locale, 'queue.progressFor').replace('{title}', title)} />}
                <div className="mt-2 flex flex-wrap items-center justify-end gap-x-3 gap-y-1">
                  <Button label={canResume ? t(locale, 'queue.continue') : t(locale, 'queue.stop')}
                    onClick={() => { if (canResume) onResume?.(item.id); else onPause?.(item.id) }}
                    disabled={busy || (!canPause && !canResume) || (canPause && !onPause) || (canResume && !onResume)}
                    className="px-2 text-small text-accent-text" />
                  <Button label={t(locale, 'queue.cancel')} onClick={() => { cancelledId.current = item.id; onCancel?.(item.id) }}
                    disabled={busy || !onCancel} className="px-2 text-small text-danger" />
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </Card>
  )
}
