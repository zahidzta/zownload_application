// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AnalyzeResult, AppError, Commands, DownloadRequest, ErrorNotification, HistoryEntry, QueueItem, Settings } from '../../shared/contract'
import { analysisUrls, offlineAnalysisScenarios, type AnalysisScenario } from './fixtures'
import { createMemoryMockStorage, defaultMockSettings, type MockStorage } from './mockStorage'
import type { AppTransport } from './types'

const youtubeHosts = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com'])

function syntheticError(code: AppError['code'], detail: string): AppError {
  return { code, detail: `Synthetic offline scenario: ${detail}` }
}

function scenarioFor(input: string): AnalysisScenario {
  if (input === offlineAnalysisScenarios.invalid.url) return offlineAnalysisScenarios.invalid

  let parsed: URL
  try {
    parsed = new URL(input)
  } catch {
    return { type: 'error', url: input, error: syntheticError('invalid_url', 'Invalid URL.') }
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return { type: 'error', url: input, error: syntheticError('invalid_url', 'Expected an HTTP(S) URL.') }
  }

  if (youtubeHosts.has(parsed.hostname)) {
    // A watch URL remains one video even when it also carries a list parameter.
    if (parsed.pathname === '/watch') {
      const id = parsed.searchParams.get('v')
      if (id === 'uW13KuRrg1g') return offlineAnalysisScenarios.single
      if (id === 'u9lj-c29dxI') return offlineAnalysisScenarios.mixed
    }
    if (parsed.pathname === '/playlist' && parsed.searchParams.get('list') === 'PL6B3937A5D230E335') {
      return offlineAnalysisScenarios.playlist
    }
    return {
      type: 'error',
      url: input,
      error: syntheticError('not_found', 'No saved YouTube analysis matches this URL.'),
    }
  }

  if (parsed.hostname === 'archive.org') {
    if (parsed.pathname === '/details/zownload-fixture-intentionally-missing-0b02') {
      return offlineAnalysisScenarios.notFound
    }
    if (parsed.pathname === new URL(analysisUrls.restricted).pathname) {
      return offlineAnalysisScenarios.restricted
    }
    return {
      type: 'error',
      url: input,
      error: syntheticError('not_found', 'No saved Archive analysis matches this URL.'),
    }
  }

  if (input === offlineAnalysisScenarios.unsupported.url) return offlineAnalysisScenarios.unsupported
  return {
    type: 'error',
    url: input,
    error: syntheticError('unsupported_site', `No offline extractor for ${parsed.hostname}.`),
  }
}

function copyResult(result: AnalyzeResult, url: string): AnalyzeResult {
  if (result.kind === 'playlist') {
    return { ...result, url, itemTitles: [...result.itemTitles] }
  }
  return {
    ...result,
    url,
    videoHeights: [...result.videoHeights],
    audioOutputBitrates: [...result.audioOutputBitrates],
  }
}

/** Scheduling is injected so later queue progress can run on a test-controlled clock. */
export interface SimulatorClock {
  now(): number
  schedule(callback: () => void, delayMs: number): () => void
}

const systemClock: SimulatorClock = {
  now: () => Date.now(),
  schedule(callback, delayMs) {
    const timer = globalThis.setTimeout(callback, delayMs)
    return () => globalThis.clearTimeout(timer)
  },
}

/** Advance scheduled simulator events without waiting for wall-clock time. */
export function createManualSimulatorClock(): SimulatorClock & { advanceBy(ms: number): void } {
  let nowMs = 0
  let nextTimerId = 0
  const timers = new Map<number, { dueMs: number; callback: () => void }>()

  return {
    now: () => nowMs,
    schedule(callback, delayMs) {
      if (!Number.isFinite(delayMs) || delayMs < 0) throw new RangeError('Invalid simulator delay')
      const id = ++nextTimerId
      timers.set(id, { dueMs: nowMs + delayMs, callback })
      return () => { timers.delete(id) }
    },
    advanceBy(ms) {
      if (!Number.isFinite(ms) || ms < 0) throw new RangeError('Invalid simulator advance')
      const targetMs = nowMs + ms
      for (;;) {
        let nextId: number | undefined
        let nextDueMs = Infinity
        for (const [id, timer] of timers) {
          if (timer.dueMs <= targetMs && timer.dueMs < nextDueMs) {
            nextId = id
            nextDueMs = timer.dueMs
          }
        }
        if (nextId === undefined) break
        const timer = timers.get(nextId)!
        timers.delete(nextId)
        nowMs = timer.dueMs
        timer.callback()
      }
      nowMs = targetMs
    },
  }
}

function copyQueueItem(item: QueueItem): QueueItem {
  return {
    ...item,
    request: { ...item.request, quality: { ...item.request.quality } },
    progress: { ...item.progress },
    error: item.error && { ...item.error },
  }
}

function requestMatchesResult(request: DownloadRequest, result: AnalyzeResult): boolean {
  if (request.isPlaylist !== (result.kind === 'playlist')) return false
  if (result.kind === 'playlist') return request.quality.type === 'max' || request.quality.type === 'min'
  if (request.format === 'mp4') {
    return request.quality.type === 'video' && result.videoHeights.includes(request.quality.height)
  }
  return request.quality.type === 'audio' && result.audioOutputBitrates.includes(request.quality.bitrate)
}

function requestKey(request: DownloadRequest): string {
  const quality = request.quality
  return JSON.stringify([request.url, request.format, request.isPlaylist, quality.type,
    quality.type === 'audio' ? quality.bitrate : quality.type === 'video' ? quality.height : null])
}

export type MockOutcome = 'success' | 'partial' | 'failed'

/** Offline queue lifecycle. The clock owns every transition, including event delivery. */
export function createSimulatorTransport({ clock = systemClock, storage = createMemoryMockStorage(), outcomes = {}, availableVideoHeights = {}, engineUpdateFails = false,
  appUpdateAvailable = false, appUpdateVersion = '0.0.2', appUpdateCheckFails = false, appUpdateInstallFails = false }: {
  clock?: SimulatorClock
  storage?: MockStorage
  outcomes?: Record<string, MockOutcome>
  availableVideoHeights?: Record<string, number[]>
  engineUpdateFails?: boolean
  appUpdateAvailable?: boolean
  appUpdateVersion?: string
  appUpdateCheckFails?: boolean
  appUpdateInstallFails?: boolean
} = {}): AppTransport {
  const saved = storage.load()
  const queue: QueueItem[] = saved?.queue.map(copyQueueItem) ?? []
  const history: HistoryEntry[] = saved?.history ?? []
  const notifications: ErrorNotification[] = saved?.notifications ?? []
  let settings: Settings = saved?.settings ?? { ...defaultMockSettings }
  const queueListeners = new Set<{ handler: (item: QueueItem) => void }>()
  const removalListeners = new Set<{ handler: (id: string) => void }>()
  const historyListeners = new Set<{ handler: () => void }>()
  const notificationListeners = new Set<{ handler: () => void }>()
  const scheduled = new Map<string, () => void>()
  let nextQueueId = saved?.nextQueueId ?? 1
  let nextHistoryId = saved?.nextHistoryId ?? 1
  let engineVersion = saved?.engineVersion ?? '2026.10.01'
  const failedEngineVersions = saved?.failedEngineVersions ?? []
  const manualEngineRetries = saved?.manualEngineRetries ?? []
  let pendingEngineVersion = saved?.pendingEngineVersion ?? null
  const revertedEngineVersion = saved?.revertedEngineVersion ?? null
  const latestEngineVersion = '2026.10.23'
  let appVersion = saved?.appVersion ?? '0.0.1'
  let latestAppVersion = saved?.latestAppVersion ?? null
  let appUpdateIsAvailable = saved?.appUpdateIsAvailable ?? false
  let appUpdateCheckedAt = saved?.appUpdateCheckedAt ?? null
  let appUpdateError = saved?.appUpdateError ?? null

  function persist() {
    storage.save({ queue, history, notifications, settings, nextQueueId, nextHistoryId, engineVersion,
      failedEngineVersions, manualEngineRetries, pendingEngineVersion, revertedEngineVersion, appVersion,
      latestAppVersion, appUpdateIsAvailable, appUpdateCheckedAt, appUpdateError })
  }

  // A recreated transport models a process restart: interrupted work waits for Continue.
  if (queue.some((item) => item.status !== 'paused')) {
    for (const item of queue) item.status = 'paused'
    persist()
  }

  function emitChanged(listeners: Set<{ handler: () => void }>) {
    for (const listener of [...listeners]) listener.handler()
  }

  function emit(item: QueueItem) {
    persist()
    for (const listener of [...queueListeners]) listener.handler(copyQueueItem(item))
  }

  function remove(item: QueueItem) {
    scheduled.get(item.id)?.()
    scheduled.delete(item.id)
    queue.splice(queue.indexOf(item), 1)
    persist()
    for (const listener of [...removalListeners]) listener.handler(item.id)
  }

  function finish(item: QueueItem) {
    const outcome = outcomes[item.request.url] ?? 'success'
    const hasSuccess = outcome !== 'failed'
    const hasFailure = outcome !== 'success'
    if (hasSuccess) {
      const key = requestKey(item.request)
      const oldIndex = history.findIndex((entry) => requestKey(entry.request) === key)
      if (oldIndex >= 0) history.splice(oldIndex, 1)
      history.unshift({ id: nextHistoryId++, request: { ...item.request, quality: { ...item.request.quality } }, title: item.title })
      persist()
      emitChanged(historyListeners)
    }
    if (hasFailure) {
      const error = syntheticError('unknown', outcome === 'partial' ? 'One playlist entry failed.' : 'Download failed.')
      notifications.unshift({ id: item.id, title: item.title, error })
      item.error = error
      persist()
      emitChanged(notificationListeners)
    }
    item.status = hasSuccess ? 'done' : 'failed'
    emit(item)
    remove(item)
  }

  function scheduleNext(item: QueueItem, callback: () => void, delayMs: number) {
    scheduled.get(item.id)?.()
    scheduled.set(item.id, clock.schedule(() => {
      scheduled.delete(item.id)
      if (queue.includes(item)) callback()
    }, delayMs))
  }

  function advance(item: QueueItem) {
    if (item.status !== 'downloading') return
    if (item.progress.kind === 'single') {
      item.progress.percent = Math.min(100, item.progress.percent + 25)
      emit(item)
      if (item.progress.percent === 100) {
        scheduleNext(item, () => {
          item.status = 'postProcessing'
          emit(item)
          scheduleNext(item, () => finish(item), 1000)
        }, 1000)
      } else scheduleNext(item, () => advance(item), 1000)
      return
    }
    const progress = item.progress
    const processed = progress.done + progress.failed
    const batch = Math.min(progress.total - processed, Math.max(1, Math.ceil(progress.total / 4)))
    const outcome = outcomes[item.request.url] ?? 'success'
    if (outcome === 'failed') progress.failed += batch
    else if (outcome === 'partial' && processed + batch === progress.total) {
      progress.done += batch - 1
      progress.failed++
    } else progress.done += batch
    const complete = progress.done + progress.failed === progress.total
    progress.currentPercent = complete ? 100 : 25
    progress.currentTitle = complete ? null : `Synthetic playlist item ${progress.done + progress.failed + 1}`
    emit(item)
    if (complete) {
      if (outcome === 'failed') {
        scheduleNext(item, () => finish(item), 1000)
        return
      }
      scheduleNext(item, () => {
        item.status = 'postProcessing'
        emit(item)
        scheduleNext(item, () => {
          item.status = 'packaging'
          emit(item)
          scheduleNext(item, () => finish(item), 1000)
        }, 1000)
      }, 1000)
    } else scheduleNext(item, () => advance(item), 1000)
  }

  function start(item: QueueItem) {
    item.status = 'downloading'
    emit(item)
    scheduleNext(item, () => advance(item), 1000)
  }

  return {
    async call<K extends keyof Commands>(command: K, args: Commands[K]['args']): Promise<Commands[K]['result']> {
      if (command === 'analyze_url') {
        const url = (args as Commands['analyze_url']['args']).url.trim()
        const scenario = scenarioFor(url)
        if (scenario.type === 'error') throw { ...scenario.error }
        return copyResult(scenario.result, url) as Commands[K]['result']
      }

      if (command === 'enqueue_download') {
        const request = (args as Commands['enqueue_download']['args']).request
        const url = request.url.trim()
        const scenario = scenarioFor(url)
        if (scenario.type === 'error') throw { ...scenario.error }
        const acceptedRequest: DownloadRequest = { ...request, url, quality: { ...request.quality } }
        if (scenario.result.kind === 'single' && request.format === 'mp4' && request.quality.type === 'video') {
          const requestedHeight = request.quality.height
          const heights = availableVideoHeights[url] ?? scenario.result.videoHeights
          if (!heights.includes(requestedHeight)) {
            const lower = heights.filter((height) => height < requestedHeight).sort((a, b) => b - a)[0]
            if (lower !== undefined) acceptedRequest.quality = { type: 'video', height: lower }
          }
        }
        if (!requestMatchesResult(acceptedRequest, scenario.result)) {
          throw syntheticError('unknown', 'Download quality or playlist flag does not match the analyzed item.')
        }

        // Stable UUID-shaped ids make enqueue order and snapshots reproducible.
        const id = `00000000-0000-4000-8000-${(nextQueueId++).toString(16).padStart(12, '0')}`
        const item: QueueItem = {
          id,
          request: acceptedRequest,
          title: scenario.result.title,
          thumbnail: scenario.result.thumbnail,
          status: 'queued',
          progress: scenario.result.kind === 'playlist'
            ? { kind: 'playlist', done: 0, failed: 0, total: scenario.result.itemCount, currentTitle: null, currentPercent: 0 }
            : { kind: 'single', percent: 0 },
          error: null,
        }
        queue.push(item)
        persist()
        clock.schedule(() => { if (queue.includes(item)) emit(item) }, 0)
        scheduleNext(item, () => start(item), 1000)
        return id as Commands[K]['result']
      }

      if (command === 'get_queue') return queue.map(copyQueueItem) as Commands[K]['result']

      if (command === 'get_history') {
        return history.map((entry) => ({ ...entry, request: { ...entry.request, quality: { ...entry.request.quality } } })) as Commands[K]['result']
      }
      if (command === 'delete_history_entry') {
        const { id } = args as Commands['delete_history_entry']['args']
        const index = history.findIndex((entry) => entry.id === id)
        if (index < 0) throw syntheticError('not_found', `History entry ${id} is missing.`)
        history.splice(index, 1)
        persist()
        emitChanged(historyListeners)
        return undefined as Commands[K]['result']
      }
      if (command === 'clear_history') {
        if (history.length) {
          history.length = 0
          persist()
          emitChanged(historyListeners)
        }
        return undefined as Commands[K]['result']
      }
      if (command === 'get_error_notifications') {
        return notifications.map((note) => ({ ...note, error: { ...note.error } })) as Commands[K]['result']
      }
      if (command === 'get_settings') return { ...settings } as Commands[K]['result']
      if (command === 'set_settings') {
        const next = (args as Commands['set_settings']['args']).settings
        if ((next.language !== 'en' && next.language !== 'es') || typeof next.zipPlaylists !== 'boolean' ||
            (next.downloadDir !== null && typeof next.downloadDir !== 'string')) {
          throw syntheticError('unknown', 'Invalid mock settings.')
        }
        settings = { ...next }
        persist()
        return undefined as Commands[K]['result']
      }
      if (command === 'app_update_check') {
        const now = clock.now()
        if (appUpdateCheckedAt === null || now - appUpdateCheckedAt >= 24 * 60 * 60 * 1000) {
          appUpdateCheckedAt = now
          if (appUpdateCheckFails) {
            appUpdateError = 'Synthetic app update check failed.'
          } else {
            latestAppVersion = appUpdateAvailable ? appUpdateVersion : null
            appUpdateIsAvailable = appUpdateAvailable
            appUpdateError = null
          }
          persist()
        }
        return {
          current: appVersion,
          latest: latestAppVersion,
          updateAvailable: appUpdateIsAvailable && latestAppVersion !== appVersion,
          checkedAt: appUpdateCheckedAt === null ? null : Math.floor(appUpdateCheckedAt / 1000),
          error: appUpdateError,
        } as Commands[K]['result']
      }
      if (command === 'app_update_install') {
        if (!appUpdateIsAvailable || latestAppVersion === null || latestAppVersion === appVersion) {
          throw syntheticError('unknown', 'No app update is available.')
        }
        if (appUpdateInstallFails) throw syntheticError('unknown', 'Mock app update installation failed.')
        appVersion = latestAppVersion
        appUpdateIsAvailable = false
        appUpdateError = null
        persist()
        return undefined as Commands[K]['result']
      }
      if (command === 'engine_check_update' || command === 'engine_update') {
        const failed = engineVersion !== latestEngineVersion && failedEngineVersions.includes(latestEngineVersion)
        const retryAvailable = failed && !manualEngineRetries.includes(latestEngineVersion)
        const info = (outcome: 'current' | 'available' | 'pending' | 'updated' | 'failed' | 'reverted') => ({
          current: engineVersion,
          latest: latestEngineVersion,
          updateAvailable: engineVersion !== latestEngineVersion && (!failed || retryAvailable) && !pendingEngineVersion,
          outcome,
          ...(pendingEngineVersion ? { pendingVersion: pendingEngineVersion } : {}),
          ...(revertedEngineVersion ? { revertedVersion: revertedEngineVersion } : {}),
          ...(failed ? { failedVersion: latestEngineVersion, manualRetryAvailable: retryAvailable } : {}),
        })
        if (command === 'engine_update') {
          if (failed && !retryAvailable) return info('failed') as Commands[K]['result']
          if (failed) manualEngineRetries.push(latestEngineVersion)
          if (engineUpdateFails) {
            if (!failed) failedEngineVersions.push(latestEngineVersion)
            persist()
            throw syntheticError('no_internet', 'Mock engine update failed.')
          }
          engineVersion = latestEngineVersion
          pendingEngineVersion = null
          persist()
          return info('updated') as Commands[K]['result']
        }
        return info(failed ? 'failed' : engineVersion === latestEngineVersion ? 'current' : 'available') as Commands[K]['result']
      }
      if (command === 'dismiss_error_notification') {
        const { id } = args as Commands['dismiss_error_notification']['args']
        const index = notifications.findIndex((note) => note.id === id)
        if (index < 0) throw syntheticError('not_found', `Error notification ${id} is missing.`)
        notifications.splice(index, 1)
        persist()
        emitChanged(notificationListeners)
        return undefined as Commands[K]['result']
      }

      if (command === 'pause_download' || command === 'resume_download' || command === 'remove_download') {
        const { id } = args as Commands['pause_download']['args']
        const item = queue.find((candidate) => candidate.id === id)
        if (!item) throw syntheticError('not_found', `Queue item ${id} is missing.`)
        if (command === 'pause_download') {
          if (item.status !== 'downloading') throw syntheticError('unknown', 'Pause is available only while downloading.')
          scheduled.get(id)?.()
          scheduled.delete(id)
          item.status = 'paused'
          clock.schedule(() => emit(item), 0)
        } else if (command === 'resume_download') {
          if (item.status !== 'paused') throw syntheticError('unknown', 'Resume is available only while paused.')
          clock.schedule(() => start(item), 0)
        } else {
          scheduled.get(id)?.()
          scheduled.delete(id)
          queue.splice(queue.indexOf(item), 1)
          persist()
          clock.schedule(() => {
            for (const listener of [...removalListeners]) listener.handler(id)
          }, 0)
        }
        return undefined as Commands[K]['result']
      }

      throw syntheticError('unknown', `Simulator command ${command} is not implemented yet.`)
    },
    async on(name, handler) {
      if (name === 'queue:item-updated') {
        const listener = { handler: handler as (item: QueueItem) => void }
        queueListeners.add(listener)
        return () => { queueListeners.delete(listener) }
      }
      if (name === 'queue:item-removed') {
        const listener = { handler: handler as (id: string) => void }
        removalListeners.add(listener)
        return () => { removalListeners.delete(listener) }
      }
      if (name === 'history:changed') {
        const listener = { handler: handler as () => void }
        historyListeners.add(listener)
        return () => { historyListeners.delete(listener) }
      }
      if (name === 'error-notifications:changed') {
        const listener = { handler: handler as () => void }
        notificationListeners.add(listener)
        return () => { notificationListeners.delete(listener) }
      }
      return () => {}
    },
  }
}
