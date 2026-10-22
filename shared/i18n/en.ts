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
    urlLabel: 'Video or playlist URL',
    analyze: 'Analyze',
  },
  queue: {
    title: 'Queue',
    empty: 'No active downloads',
  },
  history: {
    title: 'History',
    empty: 'No history yet',
  },
  settings: {
    title: 'Settings',
    language: 'Language',
  },
  errors,
} as const
