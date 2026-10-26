// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AppTransport } from './types'

/** Android still runs the separate Gate 0C spike handlers in this Windows stage. */
export function usesDesktopNativeTransport(tauri: boolean, userAgent: string): boolean {
  return tauri && !/Android/i.test(userAgent)
}

/** Desktop native commands always go through Rust; browser preview stays offline. */
export function createRuntimeTransport({ native, nativeTransport, simulatorTransport }: {
  native: boolean
  nativeTransport: AppTransport
  simulatorTransport: AppTransport | null
}): AppTransport {
  if (!native) {
    if (!simulatorTransport) throw new Error('Browser preview needs a simulator transport')
    return simulatorTransport
  }
  return nativeTransport
}
