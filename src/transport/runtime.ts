// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AppTransport } from './types'

/** Every Tauri target uses Rust; only the browser preview uses the simulator. */
export function usesTauriNativeTransport(tauri: boolean): boolean {
  return tauri
}

/** Native commands always go through Rust; browser preview stays offline. */
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
