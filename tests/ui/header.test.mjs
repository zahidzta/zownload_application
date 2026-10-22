// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import test, { after } from 'node:test'
import { createElement as h } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { createServer } from 'vite'

const vite = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom' })
after(() => vite.close())
const { useShellStore } = await vite.ssrLoadModule('/src/state/shell.ts')
const { Header, HeaderView } = await vite.ssrLoadModule('/src/components/Header.tsx')
const { t } = await vite.ssrLoadModule('/src/i18n.ts')

function resetShell() {
  useShellStore.setState({ locale: 'en', page: 'main' })
}

function renderShellCopy() {
  const shell = useShellStore.getState()
  const locale = shell.locale
  return renderToStaticMarkup(h('div', null,
    h(HeaderView, { locale, onToggleLocale: shell.toggleLocale, onOpenSettings: shell.openSettings }),
    h('main', null,
      h('h1', null, t(locale, 'input.title')),
      h('p', null, t(locale, 'queue.empty')),
      h('p', null, t(locale, 'history.empty')),
    ),
  ))
}

test('header keeps logo, name, language, and settings in the approved order', () => {
  resetShell()
  const html = renderShellCopy()
  const connectedHeader = renderToStaticMarkup(h(Header))
  const buttons = [...html.matchAll(/<button\b[^>]*>/g)].map((match) => match[0])

  assert.match(html, /<header\b[^>]*class="[^"]*sticky top-0/)
  assert.match(connectedHeader, /aria-label="Switch to Spanish"/)
  assert.match(html, /<svg aria-hidden="true"[^>]*text-primary/)
  assert.equal((html.match(/<header\b/g) ?? []).length, 1)
  assert.equal(buttons.length, 2)
  assert.ok(html.indexOf('text-primary') < html.indexOf('>zownload</span>'))
  assert.ok(html.indexOf('>zownload</span>') < html.indexOf(buttons[0]))
  assert.match(buttons[0], /type="button"/)
  assert.match(buttons[0], /aria-label="Switch to Spanish"/)
  assert.match(buttons[1], /type="button"/)
  assert.match(buttons[1], /aria-label="Settings"/)
  assert.match(html, /<span aria-hidden="true"[^>]*>EN<\/span>/)
  assert.doesNotMatch(html, /role="button"|<div[^>]*onClick=/)
})

test('language action synchronously changes header names and rendered shell copy', () => {
  resetShell()
  const observed = []
  const unsubscribe = useShellStore.subscribe((state) => observed.push(state.locale))
  const english = renderShellCopy()

  useShellStore.getState().toggleLocale()
  const spanish = renderShellCopy()
  useShellStore.getState().toggleLocale()
  const englishAgain = renderShellCopy()
  unsubscribe()

  assert.deepEqual(observed, ['es', 'en'])
  assert.match(english, /Switch to Spanish/)
  assert.match(english, /No active downloads/)
  assert.match(spanish, /aria-label="Cambiar a inglés"/)
  assert.match(spanish, /aria-label="Configuración"/)
  assert.match(spanish, /<span aria-hidden="true"[^>]*>ES<\/span>/)
  assert.match(spanish, /<h1>Descargar<\/h1>/)
  assert.match(spanish, /No hay descargas activas/)
  assert.match(spanish, /Aún no hay historial/)
  assert.doesNotMatch(spanish, /No active downloads|No history yet|Switch to Spanish/)
  assert.match(englishAgain, /aria-label="Switch to Spanish"/)
  assert.match(englishAgain, /No active downloads/)
})

test('settings action changes shell page and closing it retains the selected language', () => {
  resetShell()
  const shell = useShellStore.getState()
  shell.setLocale('es')
  shell.openSettings()
  assert.equal(useShellStore.getState().page, 'settings')
  assert.equal(useShellStore.getState().locale, 'es')

  useShellStore.getState().closeSettings()
  assert.equal(useShellStore.getState().page, 'main')
  assert.equal(useShellStore.getState().locale, 'es')
})
