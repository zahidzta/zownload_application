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

/** @type {import('../shared/contract').AnalyzeResult} */
const singleAnalyzeResult = {
  kind: 'single',
  url: 'https://example.com/media',
  title: 'Example',
  author: 'Uploader',
  thumbnail: null,
  durationSec: 60,
  site: 'Example',
  videoHeights: [720],
  audioOutputBitrates: [320, 256, 192, 128],
  estimates: [
    { format: 'mp3', quality: { type: 'audio', bitrate: 320 }, estimatedBytes: 2400000 },
    { format: 'mp4', quality: { type: 'video', height: 720 }, estimatedBytes: 8000000 },
  ],
}

const fixture = JSON.parse(
  readFileSync(new URL('../tests/contract-fixtures.json', import.meta.url), 'utf8'),
)

deepStrictEqual(JSON.parse(JSON.stringify({ downloadRequest, playlistProgress, singleAnalyzeResult })), fixture)
console.log('TypeScript contract fixtures match the shared JSON')
