// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { en } from '../shared/i18n/en'
import { es } from '../shared/i18n/es'

export const catalogs = { en, es } as const

export type Locale = keyof typeof catalogs

type LeafPaths<T> = {
  [Key in keyof T & string]: T[Key] extends string
    ? Key
    : `${Key}.${LeafPaths<T[Key]>}`
}[keyof T & string]

export type TranslationKey = LeafPaths<typeof en>

export function resolveLocale(locale: string | null | undefined): Locale {
  return locale === 'es' ? 'es' : 'en'
}

function read(catalog: object, key: TranslationKey): string | undefined {
  let value: unknown = catalog
  for (const segment of key.split('.')) {
    if (typeof value !== 'object' || value === null || !Object.hasOwn(value, segment)) {
      return undefined
    }
    value = (value as Record<string, unknown>)[segment]
  }
  return typeof value === 'string' && value.trim() ? value : undefined
}

export function t(locale: string | null | undefined, key: TranslationKey): string {
  return read(catalogs[resolveLocale(locale)], key) ?? read(en, key) ?? key
}
