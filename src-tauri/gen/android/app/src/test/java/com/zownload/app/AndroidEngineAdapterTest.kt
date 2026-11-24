// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidEngineAdapterTest {
    @Test
    fun adapterForwardsCancellationWithoutTrackingQueueState() {
        val provider = FakePackage()
        val adapter = AndroidEngineAdapter(provider)

        assertTrue(adapter.cancel("entry-1"))
        assertEquals("entry-1", provider.cancelledId)
    }

    @Test
    fun typedProviderFailuresRemainTypedAtTheAdapterBoundary() {
        val provider = FakePackage()
        val adapter = AndroidEngineAdapter(provider)
        provider.analysisError = EngineBridgeException("private_or_restricted", "Video is restricted")

        try {
            adapter.analyze("https://example.invalid/watch")
            throw AssertionError("Expected the typed provider failure")
        } catch (error: EngineBridgeException) {
            assertEquals("private_or_restricted", error.code)
            assertEquals("Video is restricted", error.message)
        }
    }

    private class FakePackage : AndroidEnginePackage {
        var cancelledId: String? = null
        var analysisError: EngineBridgeException? = null
        override fun initialize() = Unit

        override fun analyze(url: String): JSONObject {
            analysisError?.let { throw it }
            throw AssertionError("Fake analysis was not configured")
        }

        override fun downloadOne(
            request: JSONObject,
            operationId: String,
            outputTemplate: String,
            onProgress: (JSONObject) -> Unit,
        ): JSONObject = throw AssertionError("Download is not used in this unit test")

        override fun cancel(operationId: String): Boolean {
            cancelledId = operationId
            return true
        }

        override fun checkUpdate(): JSONObject = throw AssertionError("Update is not used in this unit test")

        override fun update(): JSONObject = throw AssertionError("Update is not used in this unit test")
    }
}
