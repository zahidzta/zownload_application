// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { createStore } from 'zustand/vanilla'
import type { AnalyzeResult, AppError, ErrorCode, ErrorNotification, Format, HistoryEntry, Quality, QueueItem, Settings } from '../../shared/contract'
import type { AppTransport, Unsubscribe } from '../transport/types'

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
  queueItems: QueueItem[]
  historyEntries: HistoryEntry[]
  notifications: ErrorNotification[]
  settings: Settings | null
  syncError: AppError | null
  actionError: AppError | null
  queueActionId: string | null
  queueActionTarget: 'paused' | 'downloading' | 'removed' | null
  historyActionId: number | 'clear' | null
  notificationActionId: string | null
  setUrl: (url: string) => void
  setFormat: (format: Format) => void
  analyze: () => Promise<void>
  selectQuality: (quality: Quality) => void
  back: () => void
  enqueue: () => Promise<string | null>
  pauseQueueItem: (id: string) => Promise<void>
  resumeQueueItem: (id: string) => Promise<void>
  cancelQueueItem: (id: string) => Promise<void>
  deleteHistoryEntry: (id: number) => Promise<void>
  clearHistory: () => Promise<void>
  redownload: (id: number) => Promise<string | null>
  dismissNotification: (id: string) => Promise<void>
  refreshQueue: () => Promise<void>
  refreshHistory: () => Promise<void>
  refreshNotifications: () => Promise<void>
  refreshSettings: () => Promise<void>
  retryActivity: () => Promise<void>
  connectActivity: () => Unsubscribe
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
  let connectionUsers = 0
  let connectionVersion = 0
  let disconnectors: Unsubscribe[] = []
  let queueEpoch = 0
  let historyEpoch = 0
  let notificationEpoch = 0
  let queueRead = 0
  let historyRead = 0
  let notificationRead = 0
  let settingsRead = 0

  return createStore<DownloadFlowState>()((set, get) => ({
    step: 'input',
    url: '',
    format: 'mp3',
    analyzing: false,
    error: null,
    result: null,
    selectedQuality: null,
    enqueuing: false,
    queueItems: [],
    historyEntries: [],
    notifications: [],
    settings: null,
    syncError: null,
    actionError: null,
    queueActionId: null,
    queueActionTarget: null,
    historyActionId: null,
    notificationActionId: null,
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
      let id: string
      try {
        id = await transport.call('enqueue_download', { request: {
          url: result.url,
          format,
          quality: selectedQuality,
          isPlaylist: result.kind === 'playlist',
        } })
        set({
          step: 'input', url: '', format: 'mp3', analyzing: false, error: null,
          result: null, selectedQuality: null, enqueuing: false,
        })
      } catch (reason) {
        set({
          step: 'input', analyzing: false, error: appError(reason),
          result: null, selectedQuality: null, enqueuing: false,
        })
        return null
      }
      // Acceptance is final even if the follow-up queue read needs a retry.
      await get().refreshQueue()
      return id
    },
    async pauseQueueItem(id) {
      if (get().queueActionId || !get().queueItems.some((item) => item.id === id && item.status === 'downloading')) return
      set({ queueActionId: id, queueActionTarget: 'paused', actionError: null })
      try {
        await transport.call('pause_download', { id })
        await get().refreshQueue()
      } catch (reason) {
        set({ queueActionId: null, queueActionTarget: null, actionError: appError(reason) })
      }
    },
    async resumeQueueItem(id) {
      if (get().queueActionId || !get().queueItems.some((item) => item.id === id && item.status === 'paused')) return
      set({ queueActionId: id, queueActionTarget: 'downloading', actionError: null })
      try {
        await transport.call('resume_download', { id })
        await get().refreshQueue()
      } catch (reason) {
        set({ queueActionId: null, queueActionTarget: null, actionError: appError(reason) })
      }
    },
    async cancelQueueItem(id) {
      if (get().queueActionId || !get().queueItems.some((item) => item.id === id)) return
      set({ queueActionId: id, queueActionTarget: 'removed', actionError: null })
      try {
        await transport.call('remove_download', { id })
        await get().refreshQueue()
      } catch (reason) {
        set({ queueActionId: null, queueActionTarget: null, actionError: appError(reason) })
      }
    },
    async deleteHistoryEntry(id) {
      if (get().historyActionId !== null || !get().historyEntries.some((entry) => entry.id === id)) return
      set({ historyActionId: id, actionError: null })
      try {
        await transport.call('delete_history_entry', { id })
        await get().refreshHistory()
      } catch (reason) {
        set({ actionError: appError(reason) })
      } finally {
        set({ historyActionId: null })
      }
    },
    async clearHistory() {
      if (get().historyActionId !== null || get().historyEntries.length === 0) return
      set({ historyActionId: 'clear', actionError: null })
      try {
        await transport.call('clear_history', {})
        await get().refreshHistory()
      } catch (reason) {
        set({ actionError: appError(reason) })
      } finally {
        set({ historyActionId: null })
      }
    },
    async dismissNotification(id) {
      if (get().notificationActionId !== null || !get().notifications.some((note) => note.id === id)) return
      set({ notificationActionId: id, actionError: null })
      try {
        await transport.call('dismiss_error_notification', { id })
        // Remove only after the command succeeds. The event refetch keeps other notes current.
        notificationEpoch++
        set((state) => ({ notificationActionId: null, notifications: state.notifications.filter((note) => note.id !== id) }))
        await get().refreshNotifications()
      } catch (reason) {
        set({ actionError: appError(reason) })
      } finally {
        set({ notificationActionId: null })
      }
    },
    async redownload(id) {
      const entry = get().historyEntries.find((candidate) => candidate.id === id)
      if (get().historyActionId !== null || !entry) return null
      set({ historyActionId: id, actionError: null })
      try {
        const queueId = await transport.call('enqueue_download', { request: {
          ...entry.request, quality: { ...entry.request.quality },
        } })
        // The accepted job remains accepted if the follow-up snapshot fails.
        await get().refreshQueue()
        return queueId
      } catch (reason) {
        set({ actionError: appError(reason) })
        return null
      } finally {
        set({ historyActionId: null })
      }
    },
    async refreshQueue() {
      const read = ++queueRead
      const epoch = queueEpoch
      try {
        const items = await transport.call('get_queue', {})
        if (read !== queueRead) return
        if (epoch !== queueEpoch) return get().refreshQueue()
        set((state) => {
          const completed = state.queueActionId !== null && (
            state.queueActionTarget === 'removed' ? !items.some((item) => item.id === state.queueActionId) :
              items.some((item) => item.id === state.queueActionId && item.status === state.queueActionTarget)
          )
          return { queueItems: items, ...(completed ? { queueActionId: null, queueActionTarget: null } : {}) }
        })
      } catch (reason) {
        if (read === queueRead) set({ syncError: appError(reason) })
      }
    },
    async refreshHistory() {
      const read = ++historyRead
      const epoch = historyEpoch
      try {
        const entries = await transport.call('get_history', {})
        if (read !== historyRead) return
        if (epoch !== historyEpoch) return get().refreshHistory()
        set({ historyEntries: entries })
      } catch (reason) {
        if (read === historyRead) set({ syncError: appError(reason) })
      }
    },
    async refreshNotifications() {
      const read = ++notificationRead
      const epoch = notificationEpoch
      try {
        const notes = await transport.call('get_error_notifications', {})
        if (read !== notificationRead) return
        if (epoch !== notificationEpoch) return get().refreshNotifications()
        set((state) => {
          const pending = state.notifications.find((note) => note.id === state.notificationActionId)
          return { notifications: pending && !notes.some((note) => note.id === pending.id) ? [pending, ...notes] : notes }
        })
      } catch (reason) {
        if (read === notificationRead) set({ syncError: appError(reason) })
      }
    },
    async refreshSettings() {
      const read = ++settingsRead
      try {
        const settings = await transport.call('get_settings', {})
        if (read === settingsRead) set({ settings: { ...settings } })
      } catch (reason) {
        if (read === settingsRead) set({ syncError: appError(reason) })
      }
    },
    async retryActivity() {
      set({ syncError: null })
      await Promise.all([
        get().refreshQueue(), get().refreshHistory(), get().refreshNotifications(), get().refreshSettings(),
      ])
    },
    connectActivity() {
      connectionUsers++
      if (connectionUsers === 1) {
        const version = ++connectionVersion
        void (async () => {
          const offs: Unsubscribe[] = []
          try {
            offs.push(await transport.on('queue:item-updated', (item) => {
              if (version !== connectionVersion) return
              queueEpoch++
              set((state) => {
                const index = state.queueItems.findIndex((old) => old.id === item.id)
                const completed = state.queueActionId === item.id && state.queueActionTarget === item.status
                if (index < 0) return { queueItems: [...state.queueItems, item], ...(completed ? { queueActionId: null, queueActionTarget: null } : {}) }
                const queueItems = [...state.queueItems]
                queueItems[index] = item
                return { queueItems, ...(completed ? { queueActionId: null, queueActionTarget: null } : {}) }
              })
            }))
            offs.push(await transport.on('queue:item-removed', (id) => {
              if (version !== connectionVersion) return
              queueEpoch++
              set((state) => ({ queueItems: state.queueItems.filter((item) => item.id !== id),
                ...(state.queueActionId === id ? { queueActionId: null, queueActionTarget: null } : {}) }))
            }))
            offs.push(await transport.on('history:changed', () => {
              if (version !== connectionVersion) return
              historyEpoch++
              void get().refreshHistory()
            }))
            offs.push(await transport.on('error-notifications:changed', () => {
              if (version !== connectionVersion) return
              notificationEpoch++
              void get().refreshNotifications()
            }))
            if (version !== connectionVersion) {
              offs.forEach((off) => off())
              return
            }
            disconnectors = offs
            void get().retryActivity()
          } catch (reason) {
            offs.forEach((off) => off())
            if (version === connectionVersion) set({ syncError: appError(reason) })
          }
        })()
      }
      let released = false
      return () => {
        if (released) return
        released = true
        connectionUsers--
        if (connectionUsers !== 0) return
        connectionVersion++
        disconnectors.forEach((off) => off())
        disconnectors = []
        queueRead++
        historyRead++
        notificationRead++
        settingsRead++
      }
    },
  }))
}
