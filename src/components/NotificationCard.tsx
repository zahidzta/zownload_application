// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useEffect, useRef } from 'react'
import type { ErrorNotification } from '../../shared/contract'
import type { Locale } from '../i18n'
import { t } from '../i18n'
import { IconButton } from './ui/Button'
import { Card } from './ui/Card'

interface NotificationCardProps {
  locale: Locale
  notifications: ErrorNotification[]
  busyId?: string | null
  onDismiss?: (id: string) => void
}

export function NotificationCard({ locale, notifications, busyId = null, onDismiss }: NotificationCardProps) {
  const cardRef = useRef<HTMLElement>(null)
  const dismissedId = useRef<string | null>(null)

  useEffect(() => {
    if (dismissedId.current && !notifications.some((note) => note.id === dismissedId.current)) {
      // A dismissed toast may disappear while its close button has focus.
      // Move focus to the next error, or back to a stable header control.
      const nextDismiss = cardRef.current?.querySelector<HTMLButtonElement>('button:not(:disabled)')
      const headerButton = document.querySelector<HTMLButtonElement>('header button')
      ;(nextDismiss ?? headerButton)?.focus()
      dismissedId.current = null
    }
  }, [notifications])

  if (notifications.length === 0) return null

  return (
    <Card ref={cardRef} title={t(locale, 'notifications.title')} tabIndex={-1}
      className="notification-toast rounded-card border border-border bg-card p-4 lg:p-5"
      headingClassName="text-card-title font-medium text-text">
      <ul className="mt-3 mb-0 space-y-3 p-0">
        {notifications.map((note) => {
          const title = note.title ?? t(locale, 'notifications.untitled')
          return (
            <li key={note.id} className="notification-error min-w-0 list-none rounded-control bg-field px-3 py-2">
              <p role="alert" className="m-0 wrap-break-word text-small text-text-strong">
                <span className="font-medium">{title}: </span>{t(locale, `errors.${note.error.code}`)}
              </p>
              <div className="mt-1 flex justify-end">
                <IconButton label={t(locale, 'notifications.dismissFor').replace('{title}', title)}
                  icon={<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
                    strokeLinecap="round" aria-hidden="true"><path d="M5 5l14 14M19 5L5 19" /></svg>}
                  onClick={() => { dismissedId.current = note.id; onDismiss?.(note.id) }}
                  disabled={busyId !== null || !onDismiss} className="text-danger" />
              </div>
            </li>
          )
        })}
      </ul>
    </Card>
  )
}
