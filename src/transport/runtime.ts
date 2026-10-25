// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AppTransport } from './types'

/** Android still runs the separate Gate 0C spike handlers in this Windows stage. */
export function usesDesktopNativeTransport(tauri: boolean, userAgent: string): boolean {
  return tauri && !/Android/i.test(userAgent)
}

/** Native data always goes through Rust; only development analysis uses the offline preview. */
export function createRuntimeTransport({ native, development, nativeTransport, simulatorTransport }: {
  native: boolean
  development: boolean
  nativeTransport: AppTransport
  simulatorTransport: AppTransport | null
}): AppTransport {
  if (!native) {
    if (!simulatorTransport) throw new Error('Browser preview needs a simulator transport')
    return simulatorTransport
  }
  if (!development || !simulatorTransport) return nativeTransport
  return {
    call: (command, args) => command === 'analyze_url'
      ? simulatorTransport.call(command, args)
      : nativeTransport.call(command, args),
    on: (name, handler) => nativeTransport.on(name, handler),
  }
}
