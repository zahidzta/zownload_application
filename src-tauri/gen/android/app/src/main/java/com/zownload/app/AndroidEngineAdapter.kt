// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import org.json.JSONObject

internal interface AndroidEnginePackage {
    fun initialize()
    fun analyze(url: String): JSONObject
    fun downloadOne(
        request: JSONObject,
        operationId: String,
        outputTemplate: String,
        onProgress: (JSONObject) -> Unit,
    ): JSONObject
    fun cancel(operationId: String): Boolean
    fun cancelAllActive(): Int = 0
    fun hasActiveOperations(): Boolean = false
    fun checkUpdate(): JSONObject
    fun update(): JSONObject
}

internal class EngineBridgeException(
    val code: String,
    override val message: String,
) : Exception(message)

// This class only forwards one engine operation at a time. Package paths and
// runtime details stay inside AndroidEnginePackage; Rust owns the queue.
internal class AndroidEngineAdapter(
    private val packageProvider: AndroidEnginePackage,
) {
    constructor(context: Context) : this(BundledEnginePackage(context.applicationContext))

    init {
        packageProvider.initialize()
    }

    fun analyze(url: String): JSONObject = packageProvider.analyze(url)

    fun downloadOne(
        request: JSONObject,
        operationId: String,
        outputTemplate: String,
        onProgress: (JSONObject) -> Unit,
    ): JSONObject = packageProvider.downloadOne(request, operationId, outputTemplate, onProgress)

    fun cancel(operationId: String): Boolean = packageProvider.cancel(operationId)

    fun cancelAllActive(): Int = packageProvider.cancelAllActive()

    fun hasActiveOperations(): Boolean = packageProvider.hasActiveOperations()

    fun checkUpdate(): JSONObject = packageProvider.checkUpdate()

    fun update(): JSONObject = packageProvider.update()
}
