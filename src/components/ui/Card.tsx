// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useId, type ComponentPropsWithRef } from 'react'

export type CardProps = Omit<ComponentPropsWithRef<'section'>, 'aria-label' | 'aria-labelledby'> & {
  title: string
  headingClassName?: string
}

export function Card({ title, headingClassName, children, ...props }: CardProps) {
  if (!title.trim()) throw new Error('Card title must not be empty')
  const headingId = useId()

  return (
    <section {...props} aria-labelledby={headingId}>
      <h2 id={headingId} className={headingClassName}>{title}</h2>
      {children}
    </section>
  )
}
