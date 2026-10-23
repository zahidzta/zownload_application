// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { createStore } from 'zustand/vanilla'
import type { AnalyzeResult, AppError, ErrorCode, Format, Quality } from '../../shared/contract'
import type { AppTransport } from '../transport/types'

export type DownloadStep = 'input' | 'download'

export interface DownloadFlowState {
  step: DownloadStep
  url: string
  format: Format
  analyzing: boolean
  error: AppError | null
  result: AnalyzeResult | null
  selectedQuality: Quality | null
  enqueuing: boolean
  setUrl: (url: string) => void
  setFormat: (format: Format) => void
  analyze: () => Promise<void>
  selectQuality: (quality: Quality) => void
  back: () => void
  enqueue: () => Promise<string | null>
}

const errorCodes: ReadonlySet<ErrorCode> = new Set([
  'invalid_url', 'unsupported_site', 'private_or_restricted', 'not_found',
  'no_internet', 'disk_full', 'permission_denied', 'engine_missing', 'unknown',
])

function appError(reason: unknown): AppError {
  if (typeof reason === 'object' && reason !== null && 'code' in reason &&
      typeof reason.code === 'string' && errorCodes.has(reason.code as ErrorCode)) {
    const detail = 'detail' in reason && (typeof reason.detail === 'string' || reason.detail === null)
      ? reason.detail : null
    return { code: reason.code as ErrorCode, detail }
  }
  return { code: 'unknown', detail: reason instanceof Error ? reason.message : null }
}

function firstQuality(result: AnalyzeResult, format: Format): Quality | null {
  if (result.kind === 'playlist') return { type: 'max' }
  if (format === 'mp3') {
    const bitrate = result.audioOutputBitrates[0]
    return bitrate === undefined ? null : { type: 'audio', bitrate }
  }
  const height = result.videoHeights[0]
  return height === undefined ? null : { type: 'video', height }
}

function qualityIsAvailable(result: AnalyzeResult, format: Format, quality: Quality): boolean {
  if (result.kind === 'playlist') return quality.type === 'max' || quality.type === 'min'
  if (format === 'mp3') {
    return quality.type === 'audio' && result.audioOutputBitrates.includes(quality.bitrate)
  }
  return quality.type === 'video' && result.videoHeights.includes(quality.height)
}

/** One store per injected transport keeps the UI and offline tests isolated. */
export function createDownloadFlowStore(transport: AppTransport) {
  let analysisVersion = 0

  return createStore<DownloadFlowState>()((set, get) => ({
    step: 'input',
    url: '',
    format: 'mp3',
    analyzing: false,
    error: null,
    result: null,
    selectedQuality: null,
    enqueuing: false,
    setUrl(url) {
      if (get().enqueuing || get().url === url) return
      analysisVersion++
      set({ url, step: 'input', analyzing: false, error: null, result: null, selectedQuality: null })
    },
    setFormat(format) {
      if (get().enqueuing || get().format === format) return
      analysisVersion++
      set((state) => ({
        format,
        analyzing: false,
        error: null,
        selectedQuality: state.result ? firstQuality(state.result, format) : null,
      }))
    },
    async analyze() {
      if (get().analyzing || get().enqueuing) return
      const url = get().url.trim()
      const version = ++analysisVersion
      set({ step: 'input', analyzing: true, error: null, result: null, selectedQuality: null })
      try {
        const result = await transport.call('analyze_url', { url })
        if (version !== analysisVersion) return
        set({
          step: 'download', url, analyzing: false, result,
          selectedQuality: firstQuality(result, get().format),
        })
      } catch (reason) {
        if (version !== analysisVersion) return
        set({ step: 'input', analyzing: false, error: appError(reason) })
      }
    },
    selectQuality(quality) {
      const { result, format, enqueuing } = get()
      if (enqueuing || !result || !qualityIsAvailable(result, format, quality)) return
      set({ selectedQuality: quality })
    },
    back() {
      analysisVersion++
      set({ step: 'input', analyzing: false, error: null, result: null, selectedQuality: null })
    },
    async enqueue() {
      const { result, format, selectedQuality, enqueuing } = get()
      if (enqueuing || !result || !selectedQuality ||
          !qualityIsAvailable(result, format, selectedQuality)) return null
      set({ enqueuing: true, error: null })
      try {
        const id = await transport.call('enqueue_download', { request: {
          url: result.url,
          format,
          quality: selectedQuality,
          isPlaylist: result.kind === 'playlist',
        } })
        set({
          step: 'input', url: '', format: 'mp3', analyzing: false, error: null,
          result: null, selectedQuality: null, enqueuing: false,
        })
        return id
      } catch (reason) {
        set({
          step: 'input', analyzing: false, error: appError(reason),
          result: null, selectedQuality: null, enqueuing: false,
        })
        return null
      }
    },
  }))
}
