// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

internal object NativePythonBridge {
    init {
        System.loadLibrary("zownload_python_bridge")
    }

    @JvmStatic
    external fun run(pythonLibraryPath: String, pythonHome: String, source: String): Int
}
