// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { expect, test } from 'vitest'
import type { AnalyzeResult } from '../../shared/contract'
import { t } from '../../src/i18n'
import { createDownloadFlowStore } from '../../src/state/downloadFlow'
import { analysisUrls } from '../../src/transport/fixtures'
import { createSimulatorTransport } from '../../src/transport/simulator'
import type { AppTransport } from '../../src/transport/types'

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise
    reject = rejectPromise
  })
  return { promise, resolve, reject }
}

test('single analysis uses an offered MP3 maximum and clears Input after accepted enqueue', async () => {
  const transport = createSimulatorTransport()
  const flow = createDownloadFlowStore(transport)
  expect(flow.getState()).toMatchObject({ step: 'input', url: '', format: 'mp3', analyzing: false })

  flow.getState().setUrl(`  ${analysisUrls.single}  `)
  await flow.getState().analyze()
  expect(flow.getState()).toMatchObject({
    step: 'download', url: analysisUrls.single, format: 'mp3',
    result: { kind: 'single' }, selectedQuality: { type: 'audio', bitrate: 320 },
  })
  flow.getState().selectQuality({ type: 'audio', bitrate: 128 })
  flow.getState().selectQuality({ type: 'video', height: 720 })
  expect(flow.getState().selectedQuality).toEqual({ type: 'audio', bitrate: 128 })

  const id = await flow.getState().enqueue()
  expect(id).toMatch(/^[0-9a-f-]{36}$/)
  expect((await transport.call('get_queue', {}))[0].request).toEqual({
    url: analysisUrls.single, format: 'mp3', quality: { type: 'audio', bitrate: 128 }, isPlaylist: false,
  })
  expect(flow.getState()).toMatchObject({
    step: 'input', url: '', format: 'mp3', result: null, selectedQuality: null, error: null,
  })
})

test('MP4 and playlist qualities follow the analyzed result, and Back preserves the input', async () => {
  const transport = createSimulatorTransport()
  const flow = createDownloadFlowStore(transport)
  flow.getState().setFormat('mp4')
  flow.getState().setUrl(analysisUrls.single)
  await flow.getState().analyze()
  expect(flow.getState().selectedQuality).toEqual({ type: 'video', height: 720 })
  flow.getState().selectQuality({ type: 'video', height: 1080 })
  expect(flow.getState().selectedQuality).toEqual({ type: 'video', height: 720 })
  flow.getState().back()
  expect(flow.getState()).toMatchObject({
    step: 'input', url: analysisUrls.single, format: 'mp4', result: null, selectedQuality: null,
  })

  flow.getState().setUrl(analysisUrls.playlist)
  await flow.getState().analyze()
  expect(flow.getState()).toMatchObject({ result: { kind: 'playlist', itemCount: 17 }, selectedQuality: { type: 'max' } })
  flow.getState().selectQuality({ type: 'video', height: 720 })
  expect(flow.getState().selectedQuality).toEqual({ type: 'max' })
  flow.getState().selectQuality({ type: 'min' })
  await flow.getState().enqueue()
  expect((await transport.call('get_queue', {}))[0].request).toEqual({
    url: analysisUrls.playlist, format: 'mp4', quality: { type: 'min' }, isPlaylist: true,
  })
})

test('typed analysis failures stay in Input and clear when the URL changes', async () => {
  const flow = createDownloadFlowStore(createSimulatorTransport())
  flow.getState().setUrl(analysisUrls.invalid)
  await flow.getState().analyze()
  expect(flow.getState()).toMatchObject({ step: 'input', analyzing: false, error: { code: 'invalid_url' } })
  expect(t('en', 'errors.invalid_url')).toBe('Enter a valid URL.')
  expect(t('es', 'errors.invalid_url')).toBe('Introduce una URL válida.')

  flow.getState().setUrl(analysisUrls.unsupported)
  expect(flow.getState().error).toBeNull()
  await flow.getState().analyze()
  expect(flow.getState().error?.code).toBe('unsupported_site')
})

test('an older analysis cannot replace a newer result or error after an input edit', async () => {
  const transport = createSimulatorTransport()
  const single = await transport.call('analyze_url', { url: analysisUrls.single })
  const playlist = await transport.call('analyze_url', { url: analysisUrls.playlist })
  const first = deferred<AnalyzeResult>()
  const second = deferred<AnalyzeResult>()
  const originalCall = transport.call.bind(transport)
  let analyzeCalls = 0
  transport.call = ((command, args) => {
    if (command === 'analyze_url') return ++analyzeCalls === 1 ? first.promise : second.promise
    return originalCall(command, args)
  }) as AppTransport['call']
  const flow = createDownloadFlowStore(transport)

  flow.getState().setUrl(analysisUrls.single)
  const older = flow.getState().analyze()
  flow.getState().setUrl(analysisUrls.playlist)
  const newer = flow.getState().analyze()
  expect(flow.getState().analyzing).toBe(true)
  second.resolve(playlist)
  await newer
  first.resolve(single)
  await older
  expect(flow.getState()).toMatchObject({
    step: 'download', url: analysisUrls.playlist, result: { kind: 'playlist' }, analyzing: false,
  })
})

test('Back invalidates pending analysis and prevents a late rejection from showing', async () => {
  const transport = createSimulatorTransport()
  const pending = deferred<AnalyzeResult>()
  transport.call = ((command) => {
    if (command === 'analyze_url') return pending.promise
    throw new Error(`Unexpected command: ${command}`)
  }) as AppTransport['call']
  const flow = createDownloadFlowStore(transport)
  flow.getState().setUrl(analysisUrls.single)
  const analysis = flow.getState().analyze()
  flow.getState().back()
  pending.reject({ code: 'not_found', detail: 'late' })
  await analysis
  expect(flow.getState()).toMatchObject({ step: 'input', analyzing: false, error: null, result: null })
})

test('enqueue blocks duplicate requests and reports a typed rejection in Input', async () => {
  const transport = createSimulatorTransport()
  const flow = createDownloadFlowStore(transport)
  flow.getState().setUrl(analysisUrls.single)
  await flow.getState().analyze()
  const accepted = flow.getState().enqueue()
  expect(flow.getState().enqueuing).toBe(true)
  expect(await flow.getState().enqueue()).toBeNull()
  await accepted
  expect(await transport.call('get_queue', {})).toHaveLength(1)

  const rejectingTransport = createSimulatorTransport()
  const originalCall = rejectingTransport.call.bind(rejectingTransport)
  rejectingTransport.call = ((command, args) => {
    if (command === 'enqueue_download') return Promise.reject({ code: 'permission_denied', detail: 'Synthetic rejection' })
    return originalCall(command, args)
  }) as AppTransport['call']
  const rejectedFlow = createDownloadFlowStore(rejectingTransport)
  rejectedFlow.getState().setUrl(analysisUrls.single)
  await rejectedFlow.getState().analyze()
  expect(await rejectedFlow.getState().enqueue()).toBeNull()
  expect(rejectedFlow.getState()).toMatchObject({
    step: 'input', url: analysisUrls.single, error: { code: 'permission_denied' }, enqueuing: false,
  })
  expect(await rejectingTransport.call('get_queue', {})).toEqual([])
})

test('English and Spanish contain every new flow label', () => {
  const keys = [
    'input.urlPlaceholder', 'input.formatLabel', 'input.mp3', 'input.mp4',
    'input.convert', 'input.analyzing', 'download.back', 'download.quality',
    'download.requestedMaximum', 'download.maxQuality', 'download.minQuality',
    'download.download', 'download.enqueuing', 'download.duration',
    'download.site', 'download.itemCount', 'download.itemsInList',
    'download.thumbnailUnavailable',
  ] as const
  for (const key of keys) {
    expect(t('en', key).trim()).not.toBe('')
    expect(t('es', key).trim()).not.toBe('')
    expect(t('es', key)).not.toBe(key)
  }
})
