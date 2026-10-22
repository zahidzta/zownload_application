// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

import { call, on } from '../../shared/contract'
import type { AppTransport } from './types'

/** Production adapter. The contract helpers own Tauri invoke/listen details. */
export const tauriTransport: AppTransport = { call, on }
