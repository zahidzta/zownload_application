// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
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

    @Test
    fun adapterForwardsDownloadProgressAndReturnsEngineResult() {
        val provider = FakePackage()
        val adapter = AndroidEngineAdapter(provider)
        var progress: JSONObject? = null
        val request = JSONObject()

        val result = adapter.downloadOne(request, "queue-entry-1", "cache/song.mp3") {
            progress = it
        }

        assertEquals("queue-entry-1", provider.downloadOperationId)
        assertSame(request, provider.downloadRequest)
        assertEquals("cache/song.mp3", provider.outputTemplate)
        assertSame(provider.progressPayload, progress)
        assertSame(provider.downloadResult, result)
    }

    @Test
    fun adapterForwardsEngineUpdateCalls() {
        val provider = FakePackage()
        val adapter = AndroidEngineAdapter(provider)

        assertSame(provider.updateInfo, adapter.checkUpdate())
        assertSame(provider.updateResult, adapter.update())
        assertEquals(1, provider.checkUpdateCalls)
        assertEquals(1, provider.updateCalls)
    }

    private class FakePackage : AndroidEnginePackage {
        var cancelledId: String? = null
        var analysisError: EngineBridgeException? = null
        var downloadOperationId: String? = null
        var downloadRequest: JSONObject? = null
        var outputTemplate: String? = null
        var checkUpdateCalls = 0
        var updateCalls = 0
        val progressPayload = JSONObject()
        val downloadResult = JSONObject()
        val updateInfo = JSONObject()
        val updateResult = JSONObject()
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
        ): JSONObject {
            downloadOperationId = operationId
            downloadRequest = request
            this.outputTemplate = outputTemplate
            onProgress(progressPayload)
            return downloadResult
        }

        override fun cancel(operationId: String): Boolean {
            cancelledId = operationId
            return true
        }

        override fun checkUpdate(): JSONObject {
            checkUpdateCalls += 1
            return updateInfo
        }

        override fun update(): JSONObject {
            updateCalls += 1
            return updateResult
        }
    }
}
