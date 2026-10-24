// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { ErrorCode } from '../contract'

const errors = {
  invalid_url: 'Enter a valid URL.',
  unsupported_site: 'This site is not supported.',
  private_or_restricted: 'This video is private or restricted.',
  not_found: 'This video or playlist was not found.',
  no_internet: 'No internet connection.',
  disk_full: 'Not enough storage space.',
  permission_denied: 'Storage permission denied.',
  engine_missing: 'The download engine is unavailable.',
  unknown: 'Something went wrong.',
} as const satisfies Record<ErrorCode, string>

export const en = {
  app: {
    name: 'zownload',
  },
  header: {
    language: 'Language',
    settings: 'Settings',
    english: 'English',
    spanish: 'Spanish',
    switchToEnglish: 'Switch to English',
    switchToSpanish: 'Switch to Spanish',
  },
  navigation: {
    back: 'Back to downloads',
  },
  input: {
    title: 'Download',
    urlLabel: 'Enter URL',
    analyze: 'Analyze',
    urlPlaceholder: 'https://...',
    formatLabel: 'Format',
    mp3: 'MP3 (Audio)',
    mp4: 'MP4 (Video)',
    convert: 'Convert',
    analyzing: 'Analyzing',
  },
  download: {
    back: 'Back',
    quality: 'Quality',
    requestedMaximum: 'Requested maximum',
    maxQuality: 'Max quality',
    minQuality: 'Min quality',
    download: 'Download',
    enqueuing: 'Adding to queue',
    duration: 'Duration',
    site: 'Site',
    itemCount: 'Items',
    itemsInList: 'Items in list',
    thumbnailUnavailable: 'Thumbnail unavailable',
  },
  queue: {
    title: 'Queue',
    empty: 'No active downloads',
    queued: 'Queued',
  },
  history: {
    title: 'History',
    empty: 'No history yet',
  },
  activity: {
    syncError: 'Could not load download activity. Try again.',
    retry: 'Retry loading activity',
  },
  settings: {
    title: 'Settings',
    language: 'Language',
  },
  errors,
} as const
