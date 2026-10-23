// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AnalyzeResult, AppError, Commands, DownloadRequest, QueueItem } from '../../shared/contract'
import { analysisUrls, offlineAnalysisScenarios, type AnalysisScenario } from './fixtures'
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

/** In-memory analysis and enqueue. Lifecycle progression remains for 1C. */
export function createSimulatorTransport({ clock = systemClock }: { clock?: SimulatorClock } = {}): AppTransport {
  const queue: QueueItem[] = []
  const queueListeners = new Set<{ handler: (item: QueueItem) => void }>()
  let nextQueueId = 1

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
        if (!requestMatchesResult(request, scenario.result)) {
          throw syntheticError('unknown', 'Download quality or playlist flag does not match the analyzed item.')
        }

        // Stable UUID-shaped ids make enqueue order and snapshots reproducible.
        const id = `00000000-0000-4000-8000-${(nextQueueId++).toString(16).padStart(12, '0')}`
        const item: QueueItem = {
          id,
          request: { ...request, url, quality: { ...request.quality } },
          title: scenario.result.title,
          thumbnail: scenario.result.thumbnail,
          status: 'queued',
          progress: scenario.result.kind === 'playlist'
            ? { kind: 'playlist', done: 0, failed: 0, total: scenario.result.itemCount, currentTitle: null, currentPercent: 0 }
            : { kind: 'single', percent: 0 },
          error: null,
        }
        queue.push(item)
        clock.schedule(() => {
          for (const listener of [...queueListeners]) listener.handler(copyQueueItem(item))
        }, 0)
        return id as Commands[K]['result']
      }

      if (command === 'get_queue') return queue.map(copyQueueItem) as Commands[K]['result']

      throw syntheticError('unknown', `Simulator command ${command} is not implemented yet.`)
    },
    async on(name, handler) {
      if (name !== 'queue:item-updated') return () => {}
      const listener = { handler: handler as (item: QueueItem) => void }
      queueListeners.add(listener)
      return () => { queueListeners.delete(listener) }
    },
  }
}
