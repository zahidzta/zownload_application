// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import test, { after } from 'node:test'
import { createElement as h } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { createServer } from 'vite'

const vite = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom' })
after(() => vite.close())
const { default: App, AppView } = await vite.ssrLoadModule('/src/App.tsx')
const { useShellStore } = await vite.ssrLoadModule('/src/state/shell.ts')

function resetShell() {
  useShellStore.setState({ locale: 'en', page: 'main' })
}

function renderView(locale, page) {
  return renderToStaticMarkup(h(AppView, {
    locale,
    page,
    onBack: () => {},
    onToggleLocale: () => {},
    onOpenSettings: () => {},
  }))
}

test('Settings replaces the visible main view while retaining the mounted main shell', () => {
  resetShell()
  const main = renderToStaticMarkup(h(App))
  assert.match(main, /<main[^>]*aria-labelledby="[^"]+"/)
  assert.match(main, /No active downloads/)
  assert.doesNotMatch(main, /Back to downloads/)

  const settings = renderView('en', 'settings')
  assert.match(settings, /<div hidden=""><main[^>]*aria-labelledby="[^"]+"/)
  assert.match(settings, /<main[^>]*aria-labelledby="[^"]+"[^>]*><h1[^>]*>Settings<\/h1>/)
  assert.match(settings, /<h2[^>]*>Settings<\/h2>/)
  assert.match(settings, /<button[^>]*type="button"[^>]*>Back to downloads<\/button>/)
  assert.ok(settings.indexOf('class="sticky top-0') < settings.indexOf('<main '))
  assert.match(settings, /Update engine|Download folder/)
  assert.doesNotMatch(settings, /Download new APK/)
})

test('Back navigation restores the prior main view and selected language', () => {
  resetShell()
  useShellStore.getState().setLocale('es')
  useShellStore.getState().openSettings()

  const settings = renderView('es', 'settings')
  assert.match(settings, /<h1[^>]*>Configuración<\/h1>/)
  assert.match(settings, /Volver a descargas/)
  assert.match(settings, /aria-label="Cambiar a inglés"/)

  useShellStore.getState().closeSettings()
  assert.equal(useShellStore.getState().page, 'main')
  assert.equal(useShellStore.getState().locale, 'es')
  const main = renderView('es', 'main')
  assert.match(main, /<h1[^>]*>Descargar<\/h1>/)
  assert.match(main, /No hay descargas activas/)
  assert.doesNotMatch(main, /<div hidden=""|Volver a descargas/)
})
