// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import type { Commands, Events } from '../../shared/contract'

export type Unsubscribe = () => void

/** The UI's command and event boundary, independent of the active engine. */
export interface AppTransport {
  call<K extends keyof Commands>(
    command: K,
    args: Commands[K]['args'],
  ): Promise<Commands[K]['result']>

  on<K extends keyof Events>(
    name: K,
    handler: (payload: Events[K]) => void,
  ): Promise<Unsubscribe>
}
