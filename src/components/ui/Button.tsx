// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { ComponentPropsWithRef, ReactNode } from 'react'

type NativeButtonProps = Omit<ComponentPropsWithRef<'button'>, 'children' | 'aria-label'>

export type ButtonProps = NativeButtonProps & {
  label: string
}

export type IconButtonProps = NativeButtonProps & {
  label: string
  icon: ReactNode
}

const buttonClasses = 'inline-flex min-h-11 items-center justify-center focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50'

export function Button({ label, type = 'button', className = '', ...props }: ButtonProps) {
  if (!label.trim()) throw new Error('Button label must not be empty')
  return (
    <button {...props} type={type} className={`${buttonClasses} ${className}`.trim()}>
      {label}
    </button>
  )
}

export function IconButton({ label, icon, type = 'button', className = '', ...props }: IconButtonProps) {
  if (!label.trim()) throw new Error('IconButton label must not be empty')
  return (
    <button {...props} type={type} aria-label={label} className={`${buttonClasses} min-w-11 ${className}`.trim()}>
      <span aria-hidden="true">{icon}</span>
    </button>
  )
}
