// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { AppTransport } from './types'

export type { AppTransport, Unsubscribe } from './types'

/** Bind UI consumers to an injected implementation without loading Tauri. */
export function createAppTransport(implementation: AppTransport): AppTransport {
  return {
    call: (command, args) => implementation.call(command, args),
    on: (name, handler) => implementation.on(name, handler),
  }
}
