// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin

@InvokeArg
class SmokeArgs {
    lateinit var value: String
}

@TauriPlugin
class AndroidSpikePlugin(activity: Activity) : Plugin(activity) {
    @Command
    fun smoke(invoke: Invoke) {
        val args = invoke.parseArgs(SmokeArgs::class.java)
        val reply = JSObject()
        reply.put("value", args.value)
        invoke.resolve(reply)
    }
}
