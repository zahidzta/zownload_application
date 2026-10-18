// @ts-check
import { deepStrictEqual } from 'node:assert/strict'
import { readFileSync } from 'node:fs'

/** @type {import('../shared/contract').DownloadRequest} */
const downloadRequest = {
  url: 'https://example.com/media',
  format: 'mp3',
  quality: { type: 'audio', bitrate: 320 },
  isPlaylist: false,
}

/** @type {import('../shared/contract').Progress} */
const playlistProgress = {
  kind: 'playlist',
  done: 2,
  failed: 1,
  total: 5,
  currentTitle: 'Example',
  currentPercent: 42.5,
}

const fixture = JSON.parse(
  readFileSync(new URL('../tests/contract-fixtures.json', import.meta.url), 'utf8'),
)

deepStrictEqual(JSON.parse(JSON.stringify({ downloadRequest, playlistProgress })), fixture)
console.log('TypeScript contract fixtures match the shared JSON')
