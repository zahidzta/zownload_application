// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { afterEach, expect, test, vi } from 'vitest'
import type { DownloadRequest, QueueItem } from '../../shared/contract'
import { analysisUrls, selectPlaylistThumbnail } from '../../src/transport/fixtures'
import { createManualSimulatorClock, createSimulatorTransport } from '../../src/transport/simulator'
import { createBrowserMockStorage, createMemoryMockStorage } from '../../src/transport/mockStorage'

afterEach(() => vi.unstubAllGlobals())

test('observed short video has contract-shaped metadata and a bundled thumbnail', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)

  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.single })

  expect(result).toMatchObject({
    kind: 'single',
    url: analysisUrls.single,
    title: '10號風...',
    author: 'vgocyl',
    durationSec: 15,
    site: 'YouTube',
    videoHeights: [720, 360, 144],
    audioOutputBitrates: [320, 256, 192, 128],
  })
  expect(result.thumbnail).toMatch(/single-video-thumbnail.*\.jpg/)
  expect(result).not.toHaveProperty('estimates')
  expect(fetchSpy).not.toHaveBeenCalled()
})

test('pure playlist exposes its saved cover and all 17 titles without a remote image', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)
  const result = await createSimulatorTransport().call('analyze_url', { url: analysisUrls.playlist })

  expect(result.kind).toBe('playlist')
  if (result.kind !== 'playlist') throw new Error('Expected playlist')
  expect(result.itemCount).toBe(17)
  expect(result.itemTitles).toHaveLength(result.itemCount)
  expect(result.itemTitles).toContain('WING IT! - Blender Open Movie')
  expect(result.itemTitles).toContain('CHARGE - Blender Open Movie')
  expect(result.itemTitles.at(-1)).toBe('Elephants Dream')
  expect(result.thumbnail).toBe('/fixtures/blender-playlist-cover.jpg')
  expect(fetchSpy).not.toHaveBeenCalled()
})

test('playlist preview artwork prefers the playlist cover, then the first entry cover', () => {
  const cover = '/fixtures/blender-playlist-cover.jpg'
  const firstEntry = '/fixtures/blender-first-entry-cover.jpg'
  expect(selectPlaylistThumbnail(cover, firstEntry)).toBe(cover)
  expect(selectPlaylistThumbnail(null, firstEntry)).toBe(firstEntry)
  expect(selectPlaylistThumbnail(null, null)).toBeNull()
})

test('watch plus list resolves to its single video even when query order changes', async () => {
  const url = 'https://www.youtube.com/watch?list=PL6B3937A5D230E335&v=u9lj-c29dxI'
  const result = await createSimulatorTransport().call('analyze_url', { url })

  expect(result).toMatchObject({
    kind: 'single',
    url,
    title: 'WING IT! - Blender Open Movie',
    durationSec: 238,
    videoHeights: [1080, 720, 480, 360, 240, 144],
  })
})

test.each([
  [analysisUrls.invalid, 'invalid_url', "ERROR: [generic] 'not-a-url' is not a valid URL"],
  [analysisUrls.unsupported, 'unsupported_site', 'Synthetic offline scenario:'],
  [analysisUrls.notFound, 'not_found', 'HTTP Error 404: Not Found'],
  [analysisUrls.restricted, 'private_or_restricted', 'HTTP Error 401: Unauthorized'],
])('%s rejects with %s and diagnostic detail', async (url, code, detail) => {
  await expect(createSimulatorTransport().call('analyze_url', { url })).rejects.toMatchObject({
    code,
    detail: expect.stringContaining(detail),
  })
})

test('unknown inputs stay typed, and a caller cannot mutate stored fixture arrays', async () => {
  const transport = createSimulatorTransport()
  await expect(transport.call('analyze_url', { url: 'not another URL' })).rejects.toMatchObject({
    code: 'invalid_url',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })
  await expect(transport.call('analyze_url', { url: 'https://www.youtube.com/watch?v=other' })).rejects.toMatchObject({
    code: 'not_found',
    detail: expect.stringContaining('Synthetic offline scenario:'),
  })

  const first = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (first.kind !== 'playlist') throw new Error('Expected playlist')
  first.itemTitles[0] = 'Changed by caller'
  const second = await transport.call('analyze_url', { url: analysisUrls.playlist })
  if (second.kind !== 'playlist') throw new Error('Expected playlist')
  expect(second.itemTitles[0]).toBe('SINGULARITY - Painterly Space Adventure')
})

test('enqueue returns distinct ids and ordered queued snapshots for single and playlist requests', async () => {
  const fetchSpy = vi.fn(() => { throw new Error('Unexpected network request') })
  vi.stubGlobal('fetch', fetchSpy)
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const events: QueueItem[] = []
  await transport.on('queue:item-updated', item => { events.push(item) })
  const single: DownloadRequest = {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  }
  const playlist: DownloadRequest = {
    url: analysisUrls.playlist, format: 'mp3', quality: { type: 'max' }, isPlaylist: true,
  }

  const firstId = await transport.call('enqueue_download', { request: single })
  const secondId = await transport.call('enqueue_download', { request: playlist })
  expect(firstId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/)
  expect(secondId).not.toBe(firstId)

  const queue = await transport.call('get_queue', {})
  expect(queue).toEqual([
    {
      id: firstId, request: single, title: '10號風...', thumbnail: expect.stringMatching(/single-video-thumbnail.*\.jpg/),
      status: 'queued', progress: { kind: 'single', percent: 0 }, error: null,
    },
    {
      id: secondId, request: playlist, title: 'Official Blender Open Movies',
      thumbnail: '/fixtures/blender-playlist-cover.jpg', status: 'queued',
      progress: { kind: 'playlist', done: 0, failed: 0, total: 17, currentTitle: null, currentPercent: 0 },
      error: null,
    },
  ])
  expect(events).toEqual([])
  clock.advanceBy(0)
  expect(events).toEqual(queue)
  expect(fetchSpy).not.toHaveBeenCalled()

  // Queue reads and event payloads must not let the UI change simulator state.
  queue[0].request.url = 'changed by caller'
  events[1].title = 'changed by listener'
  expect((await transport.call('get_queue', {}))[0].request.url).toBe(analysisUrls.single)
  expect((await transport.call('get_queue', {}))[1].title).toBe('Official Blender Open Movies')
})

test('queue subscriptions can be removed independently and repeatedly', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const first = vi.fn()
  const second = vi.fn()
  const unsubscribeFirst = await transport.on('queue:item-updated', first)
  const unsubscribeSecond = await transport.on('queue:item-updated', second)
  const request: DownloadRequest = {
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  }

  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(1)
  expect(second).toHaveBeenCalledTimes(1)

  unsubscribeFirst()
  unsubscribeFirst()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(1)
  expect(second).toHaveBeenCalledTimes(2)

  unsubscribeSecond()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(second).toHaveBeenCalledTimes(2)
  expect(await transport.call('get_queue', {})).toHaveLength(3)

  const removeOneCopy = await transport.on('queue:item-updated', first)
  const removeOtherCopy = await transport.on('queue:item-updated', first)
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(3)
  removeOneCopy()
  await transport.call('enqueue_download', { request })
  clock.advanceBy(0)
  expect(first).toHaveBeenCalledTimes(4)
  removeOtherCopy()
})

test('enqueue rejects invalid or mismatched requests without creating a queue item', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const listener = vi.fn()
  await transport.on('queue:item-updated', listener)
  await expect(transport.call('enqueue_download', { request: {
    url: analysisUrls.invalid, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  } })).rejects.toMatchObject({ code: 'invalid_url' })
  await expect(transport.call('enqueue_download', { request: {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  } })).rejects.toMatchObject({ code: 'unknown', detail: expect.stringContaining('Synthetic offline scenario:') })
  clock.advanceBy(0)
  expect(listener).not.toHaveBeenCalled()
  expect(await transport.call('get_queue', {})).toEqual([])
})

test('single lifecycle pauses only during download and resumes from recorded progress', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const statuses: string[] = []
  const snapshots: QueueItem[] = []
  await transport.on('queue:item-updated', (item) => {
    statuses.push(item.status)
    snapshots.push(item)
  })
  const id = await transport.call('enqueue_download', { request: {
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  } })
  await expect(transport.call('pause_download', { id })).rejects.toMatchObject({ code: 'unknown' })
  clock.advanceBy(0)
  clock.advanceBy(2000)
  expect(snapshots.at(-1)?.progress).toEqual({ kind: 'single', percent: 25 })
  await transport.call('pause_download', { id })
  clock.advanceBy(0)
  clock.advanceBy(5000)
  expect((await transport.call('get_queue', {}))[0]).toMatchObject({ status: 'paused', progress: { percent: 25 } })
  await transport.call('resume_download', { id })
  clock.advanceBy(0)
  clock.advanceBy(4000)
  expect(statuses).toEqual([
    'queued', 'downloading', 'downloading', 'paused', 'downloading',
    'downloading', 'downloading', 'downloading', 'postProcessing',
  ])
  await expect(transport.call('pause_download', { id })).rejects.toMatchObject({ code: 'unknown' })
})

test('playlist reaches packaging and removal cancels scheduled progress and subscriptions', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock })
  const statuses: string[] = []
  const removed: string[] = []
  const off = await transport.on('queue:item-updated', (item) => statuses.push(item.status))
  const offRemoved = await transport.on('queue:item-removed', (id) => removed.push(id))
  const id = await transport.call('enqueue_download', { request: {
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'min' }, isPlaylist: true,
  } })
  clock.advanceBy(7000)
  expect(statuses).toContain('postProcessing')
  expect(statuses).toContain('packaging')
  expect((await transport.call('get_queue', {}))[0].progress).toMatchObject({ kind: 'playlist', done: 17, total: 17 })
  await expect(transport.call('pause_download', { id })).rejects.toMatchObject({ code: 'unknown' })
  await transport.call('remove_download', { id })
  clock.advanceBy(0)
  expect(removed).toEqual([id])
  expect(await transport.call('get_queue', {})).toEqual([])
  off()
  offRemoved()
  clock.advanceBy(10000)
  expect(removed).toEqual([id])
  await expect(transport.call('resume_download', { id })).rejects.toMatchObject({ code: 'not_found' })
})

test('terminal persistence precedes queue removal, and repeated requests replace history in newest order', async () => {
  const clock = createManualSimulatorClock()
  const storage = createMemoryMockStorage()
  const transport = createSimulatorTransport({ clock, storage, outcomes: { [analysisUrls.playlist]: 'partial' } })
  const events: string[] = []
  await transport.on('history:changed', () => events.push('history'))
  await transport.on('error-notifications:changed', () => events.push('notification'))
  await transport.on('queue:item-removed', () => events.push('removed'))
  const playlist: DownloadRequest = {
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'max' }, isPlaylist: true,
  }
  const single: DownloadRequest = {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  }
  const firstId = await transport.call('enqueue_download', { request: playlist })
  clock.advanceBy(8000)
  expect(events).toEqual(['history', 'notification', 'removed'])
  expect(await transport.call('get_queue', {})).toEqual([])
  expect(await transport.call('get_history', {})).toMatchObject([{ request: playlist }])
  expect(await transport.call('get_error_notifications', {})).toMatchObject([{ id: firstId }])

  await transport.call('enqueue_download', { request: single })
  clock.advanceBy(7000)
  await transport.call('enqueue_download', { request: playlist })
  clock.advanceBy(8000)
  const history = await transport.call('get_history', {})
  expect(history).toHaveLength(2)
  expect(history.map((entry) => entry.request)).toEqual([playlist, single])
  expect(history[0].id).toBeGreaterThan(history[1].id)
  expect((await createSimulatorTransport({ storage }).call('get_history', {}))).toEqual(history)
  await transport.call('delete_history_entry', { id: history[1].id })
  await transport.call('dismiss_error_notification', { id: firstId })
  const reloaded = createSimulatorTransport({ storage })
  expect(await reloaded.call('get_history', {})).toHaveLength(1)
  expect(await reloaded.call('get_error_notifications', {})).toHaveLength(1)
  await reloaded.call('clear_history', {})
  expect(await createSimulatorTransport({ storage }).call('get_history', {})).toEqual([])
})

test('all-failed playlist writes a notification without history, while equal titles may have distinct rows', async () => {
  const clock = createManualSimulatorClock()
  const transport = createSimulatorTransport({ clock, outcomes: { [analysisUrls.playlist]: 'failed' } })
  const playlist: DownloadRequest = {
    url: analysisUrls.playlist, format: 'mp3', quality: { type: 'max' }, isPlaylist: true,
  }
  await transport.call('enqueue_download', { request: playlist })
  clock.advanceBy(7000)
  expect(await transport.call('get_history', {})).toEqual([])
  expect(await transport.call('get_error_notifications', {})).toHaveLength(1)
  expect(await transport.call('get_queue', {})).toEqual([])

  const successClock = createManualSimulatorClock()
  const success = createSimulatorTransport({ clock: successClock })
  const first = { ...playlist, quality: { type: 'max' } as const }
  const second = { ...playlist, quality: { type: 'min' } as const }
  await success.call('enqueue_download', { request: first })
  await success.call('enqueue_download', { request: second })
  successClock.advanceBy(8000)
  const history = await success.call('get_history', {})
  expect(history).toHaveLength(2)
  expect(history[0].title).toBe(history[1].title)
  expect(history[0].id).not.toBe(history[1].id)
})

test('redownload uses the closest lower available video height', async () => {
  const transport = createSimulatorTransport({ availableVideoHeights: { [analysisUrls.single]: [360, 144] } })
  await transport.call('enqueue_download', { request: {
    url: analysisUrls.single, format: 'mp4', quality: { type: 'video', height: 720 }, isPlaylist: false,
  } })
  expect((await transport.call('get_queue', {}))[0].request.quality).toEqual({ type: 'video', height: 360 })
})

test('settings, update result, and interrupted queue survive transport recreation without auto-resume', async () => {
  const clock = createManualSimulatorClock()
  const storage = createMemoryMockStorage()
  const first = createSimulatorTransport({ clock, storage })
  const settings = { language: 'es' as const, zipPlaylists: true, downloadDir: 'C:/Downloads/Zownload' }
  await first.call('set_settings', { settings })
  const fetched = await first.call('get_settings', {})
  fetched.downloadDir = 'changed by caller'
  expect(await first.call('get_settings', {})).toEqual(settings)
  expect(await first.call('engine_check_update', {})).toMatchObject({ updateAvailable: true })
  expect(await first.call('engine_update', {})).toMatchObject({ updateAvailable: false })
  const id = await first.call('enqueue_download', { request: {
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  } })
  clock.advanceBy(3000)
  const progress = (await first.call('get_queue', {}))[0].progress
  const restartClock = createManualSimulatorClock()
  const restarted = createSimulatorTransport({ clock: restartClock, storage })
  expect(await restarted.call('get_settings', {})).toEqual(settings)
  expect(await restarted.call('engine_check_update', {})).toMatchObject({ updateAvailable: false })
  expect((await restarted.call('get_queue', {}))[0]).toMatchObject({ id, status: 'paused', progress })
  restartClock.advanceBy(10000)
  expect((await restarted.call('get_queue', {}))[0]).toMatchObject({ status: 'paused', progress })
  await restarted.call('resume_download', { id })
  restartClock.advanceBy(0)
  expect((await restarted.call('get_queue', {}))[0]).toMatchObject({ status: 'downloading', progress })
  restartClock.advanceBy(1000)
  expect((await restarted.call('get_queue', {}))[0].progress).toEqual({ kind: 'single', percent: 75 })
})

test('browser-backed mock storage round-trips and failed update stays typed', async () => {
  const entries = new Map<string, string>()
  const browserStorage = {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => { entries.set(key, value) },
  } as Storage
  const storage = createBrowserMockStorage(browserStorage, 'isolated-test')
  const first = createSimulatorTransport({ storage, engineUpdateFails: true })
  await first.call('set_settings', { settings: { language: 'es', zipPlaylists: false, downloadDir: null } })
  await expect(first.call('engine_update', {})).rejects.toMatchObject({ code: 'no_internet' })
  const reloaded = createSimulatorTransport({ storage })
  expect(await reloaded.call('get_settings', {})).toEqual({ language: 'es', zipPlaylists: false, downloadDir: null })
  expect(await reloaded.call('engine_check_update', {})).toMatchObject({
    updateAvailable: true, outcome: 'failed', failedVersion: '2026.10.23', manualRetryAvailable: true,
  })
  expect(await reloaded.call('engine_update', {})).toMatchObject({
    updateAvailable: false, outcome: 'updated', current: '2026.10.23',
  })
  const afterRetry = createSimulatorTransport({ storage })
  expect(await afterRetry.call('engine_check_update', {})).toMatchObject({
    updateAvailable: false, outcome: 'current', current: '2026.10.23',
  })
})
