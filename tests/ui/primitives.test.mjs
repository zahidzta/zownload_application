// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import assert from 'node:assert/strict'
import test, { after } from 'node:test'
import { createElement as h } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { createServer } from 'vite'

const vite = await createServer({ server: { middlewareMode: true, hmr: false }, appType: 'custom' })
after(() => vite.close())
const { Page } = await vite.ssrLoadModule('/src/components/ui/Page.tsx')
const { Card } = await vite.ssrLoadModule('/src/components/ui/Card.tsx')
const { Button, IconButton } = await vite.ssrLoadModule('/src/components/ui/Button.tsx')
const { t } = await vite.ssrLoadModule('/src/i18n.ts')

test('page and cards render named landmarks with unique heading IDs and correct hierarchy', () => {
  const html = renderToStaticMarkup(h(Page, { title: t('en', 'input.title'), className: 'page-hook' },
    h(Card, { title: t('en', 'queue.title'), className: 'card-hook', headingClassName: 'heading-hook' }, t('en', 'queue.empty')),
    h(Card, { title: t('en', 'history.title') }, t('en', 'history.empty')),
  ))

  const mainId = html.match(/<main\b[^>]*aria-labelledby="([^"]+)"/)?.[1]
  const cardIds = [...html.matchAll(/<section\b[^>]*aria-labelledby="([^"]+)"/g)].map((match) => match[1])
  assert.ok(mainId)
  assert.equal(cardIds.length, 2)
  assert.equal(new Set([mainId, ...cardIds]).size, 3)
  assert.ok(html.includes(`<h1 id="${mainId}">Download</h1>`))
  assert.ok(html.includes(`<h2 id="${cardIds[0]}" class="heading-hook">Queue</h2>`))
  assert.ok(html.includes(`<h2 id="${cardIds[1]}">History</h2>`))
  assert.ok(html.indexOf('<main') < html.indexOf('<h1'))
  assert.ok(html.indexOf('<h1') < html.indexOf('<section'))
  assert.ok(html.includes('class="page-hook"'))
  assert.ok(html.includes('class="card-hook"'))
  assert.equal((html.match(/<main\b/g) ?? []).length, 1)
})

test('buttons have native keyboard semantics, accessible names, disabled state, and class hooks', () => {
  const html = renderToStaticMarkup(h('div', null,
    h(Button, { label: t('es', 'input.analyze'), disabled: true, className: 'action-hook' }),
    h(IconButton, { label: t('en', 'header.settings'), icon: h('svg', { viewBox: '0 0 24 24' }), disabled: true }),
    h(Button, { label: 'Submit', type: 'submit' }),
  ))

  assert.equal((html.match(/<button\b/g) ?? []).length, 3)
  assert.equal((html.match(/disabled=""/g) ?? []).length, 2)
  assert.match(html, /<button(?=[^>]*type="button")(?=[^>]*disabled="")[^>]*>Analizar<\/button>/)
  assert.match(html, /<button[^>]*aria-label="Settings"[^>]*><span aria-hidden="true"><svg/)
  assert.match(html, /<button[^>]*type="submit"[^>]*>Submit<\/button>/)
  assert.match(html, /action-hook/)
  assert.match(html, /focus-visible:outline-2/)
  assert.doesNotMatch(html, /role="button"|<div[^>]*onClick=/)
})

test('empty landmark titles and button names are rejected', () => {
  for (const [Component, props] of [
    [Page, { title: ' ' }],
    [Card, { title: '' }],
    [Button, { label: '' }],
    [IconButton, { label: ' ', icon: h('svg') }],
  ]) {
    assert.throws(() => renderToStaticMarkup(h(Component, props)), /must not be empty/)
  }
})
