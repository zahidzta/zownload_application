// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { useId, type ComponentPropsWithRef } from 'react'

export type PageProps = Omit<ComponentPropsWithRef<'main'>, 'aria-label' | 'aria-labelledby'> & {
  title: string
  headingClassName?: string
}

export function Page({ title, headingClassName, children, ...props }: PageProps) {
  if (!title.trim()) throw new Error('Page title must not be empty')
  const headingId = useId()

  return (
    <main {...props} aria-labelledby={headingId}>
      <h1 id={headingId} className={headingClassName}>{title}</h1>
      {children}
    </main>
  )
}
