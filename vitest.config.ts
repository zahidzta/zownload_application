// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    include: ['tests/interactive/**/*.test.ts', 'tests/interactive/**/*.test.tsx'],
    setupFiles: ['tests/interactive/setup.ts'],
  },
})
