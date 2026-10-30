// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { ErrorNotification, HistoryEntry, QueueItem, Settings } from '../../shared/contract'

/** Replaceable mock data, intentionally separate from the later Rust SQLite store. */
export interface MockSnapshot {
  queue: QueueItem[]
  history: HistoryEntry[]
  notifications: ErrorNotification[]
  settings: Settings
  nextQueueId: number
  nextHistoryId: number
  engineVersion?: string
  failedEngineVersions?: string[]
  manualEngineRetries?: string[]
  pendingEngineVersion?: string | null
  revertedEngineVersion?: string | null
  appVersion?: string
  latestAppVersion?: string | null
  appUpdateIsAvailable?: boolean
  appUpdateCheckedAt?: number | null
  appUpdateError?: string | null
}

export interface MockStorage {
  load(): MockSnapshot | null
  save(snapshot: MockSnapshot): void
}

export const defaultMockSettings: Settings = {
  language: 'en', zipPlaylists: false, downloadDir: null,
}

function copy(snapshot: MockSnapshot): MockSnapshot {
  return JSON.parse(JSON.stringify(snapshot)) as MockSnapshot
}

export function createMemoryMockStorage(): MockStorage {
  let value: MockSnapshot | null = null
  return {
    load: () => value && copy(value),
    save(snapshot) { value = copy(snapshot) },
  }
}

export function createBrowserMockStorage(storage: Storage, key = 'zownload:mock:v1'): MockStorage {
  return {
    load() {
      try {
        const value = storage.getItem(key)
        return value ? JSON.parse(value) as MockSnapshot : null
      } catch {
        return null
      }
    },
    save(snapshot) { storage.setItem(key, JSON.stringify(snapshot)) },
  }
}
