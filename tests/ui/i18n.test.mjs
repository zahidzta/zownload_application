// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test, { after } from 'node:test'
import { createServer } from 'vite'

const vite = await createServer({ server: { middlewareMode: true }, appType: 'custom' })
after(() => vite.close())
const { catalogs: { en, es }, resolveLocale, t } = await vite.ssrLoadModule('/src/i18n.ts')

function leafKeys(catalog, prefix = '') {
  return Object.entries(catalog).flatMap(([key, value]) => {
    const path = prefix ? `${prefix}.${key}` : key
    if (typeof value === 'string') {
      assert.ok(value.trim(), `${path} must not be blank`)
      return [path]
    }
    assert.ok(value && typeof value === 'object' && !Array.isArray(value), `${path} must be a group`)
    return leafKeys(value, path)
  })
}

test('English and Spanish catalogs have the same nested, nonempty keys', () => {
  assert.deepEqual(leafKeys(es).sort(), leafKeys(en).sort())
})

test('every contract ErrorCode has exactly one entry in each catalog', () => {
  const contract = readFileSync(new URL('../../shared/contract.ts', import.meta.url), 'utf8')
  const declaration = contract.match(/export type ErrorCode\s*=\s*([^;]+);/)
  assert.ok(declaration, 'ErrorCode declaration must be readable')
  const codes = [...declaration[1].matchAll(/["']([^"']+)["']/g)].map((match) => match[1]).sort()
  assert.ok(codes.length > 0, 'ErrorCode must contain literal codes')
  assert.deepEqual(Object.keys(en.errors).sort(), codes)
  assert.deepEqual(Object.keys(es.errors).sort(), codes)
})

test('lookup switches language immediately and falls back to English', () => {
  assert.equal(t('en', 'queue.empty'), 'No active downloads')
  assert.equal(t('es', 'queue.empty'), 'No hay descargas activas')
  assert.equal(t('en', 'errors.invalid_url'), 'Enter a valid URL.')
  assert.equal(t('es', 'errors.invalid_url'), 'Introduce una URL válida.')
  assert.equal(resolveLocale('es'), 'es')
  assert.equal(resolveLocale('fr'), 'en')
  assert.equal(t('fr', 'history.empty'), en.history.empty)
  assert.equal(t(null, 'history.empty'), en.history.empty)
})

test('lookup uses English when a selected translation is empty at runtime', () => {
  const original = es.history.empty
  try {
    es.history.empty = ''
    assert.equal(t('es', 'history.empty'), en.history.empty)
  } finally {
    es.history.empty = original
  }
})
