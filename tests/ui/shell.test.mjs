// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import test, { after } from 'node:test'
import { createElement as h } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { createServer } from 'vite'

const vite = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom' })
after(() => vite.close())
const { AppShell, AppShellView } = await vite.ssrLoadModule('/src/components/AppShell.tsx')
const { default: App } = await vite.ssrLoadModule('/src/App.tsx')
const { useShellStore } = await vite.ssrLoadModule('/src/state/shell.ts')

test('desktop shell places the main slot before Queue and History in the right column', () => {
  useShellStore.setState({ locale: 'en', page: 'main' })
  const html = renderToStaticMarkup(h(AppShell, null, h('section', { 'data-slot': 'main' }, 'Main slot')))

  assert.equal((html.match(/<main\b/g) ?? []).length, 1)
  assert.match(html, /<main[^>]*aria-labelledby="[^"]+"/)
  assert.match(html, /grid-cols-1[^\"]*lg:grid-cols-\[minmax\(0,2fr\)_minmax\(0,1fr\)\]/)
  assert.match(html, /px-shell-inline/)
  assert.match(html, /<div class="app-shell-main min-w-0 lg:col-start-1"><section data-slot="main">/)
  assert.match(html, /<div class="flex min-w-0 flex-col gap-stack lg:col-start-2 lg:gap-5">/)
  assert.ok(html.indexOf('Main slot') < html.indexOf('>Queue</h2>'))
  assert.ok(html.indexOf('>Queue</h2>') < html.indexOf('>History</h2>'))
  assert.match(html, /No active downloads/)
  assert.match(html, /No history yet/)
  assert.doesNotMatch(html, /Gate 0C|Refresh from Rust|Start one item/)
})

test('running app uses a static main card and the shell localizes empty cards', () => {
  const appHtml = renderToStaticMarkup(h(App))
  const html = renderToStaticMarkup(h(AppShellView, { locale: 'es' }, h('section', null, 'Main slot')))

  assert.match(appHtml, /<h2[^>]*>Download<\/h2>/)
  assert.doesNotMatch(appHtml, /Gate 0C|<form\b/)
  assert.match(html, /<h1[^>]*>Descargar<\/h1>/)
  assert.match(html, /<h2[^>]*>Cola<\/h2>/)
  assert.match(html, /No hay descargas activas/)
  assert.match(html, /<h2[^>]*>Historial<\/h2>/)
  assert.match(html, /Aún no hay historial/)
  assert.equal((html.match(/<section\b/g) ?? []).length, 3)
  assert.doesNotMatch(html, /No active downloads|No history yet|<form\b/)
})
