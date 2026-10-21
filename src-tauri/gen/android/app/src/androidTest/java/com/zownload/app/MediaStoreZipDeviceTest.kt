// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Intent
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaStoreZipDeviceTest {
    @Test
    fun rustStreamsZipAndDeletesFailedPendingRow() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        try {
            val deadline = System.currentTimeMillis() + 30_000
            var webView: WebView? = null
            while (webView == null && System.currentTimeMillis() < deadline) {
                instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
                if (webView == null) Thread.sleep(200)
            }
            assertTrue("Tauri WebView did not appear", webView != null)
            val view = webView!!
            while (System.currentTimeMillis() < deadline) {
                if (evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") == "function") break
                Thread.sleep(200)
            }
            assertTrue("Tauri invoke bridge did not load", evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")

            val published = runProbe(instrumentation, view, false)
            Log.i("Zownload0C13", "ZIP_TEST_PUBLISHED $published")
            assertTrue("Rust ZIP publish failed: $published", published.startsWith("OK:"))

            val failed = runProbe(instrumentation, view, true)
            Log.i("Zownload0C13", "ZIP_TEST_FAILED $failed")
            assertTrue("Injected ZIP failure did not propagate: $failed", failed.startsWith("ERR:Injected ZIP failure"))
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun runProbe(instrumentation: android.app.Instrumentation, webView: WebView, fail: Boolean): String {
        evaluate(instrumentation, webView, """
            window.__zipProbeResult = '';
            window.__TAURI_INTERNALS__.invoke('probe_mediastore_zip', {fail: $fail})
              .then(value => { window.__zipProbeResult = 'OK:' + JSON.stringify(value); },
                    error => { window.__zipProbeResult = 'ERR:' + String(error); });
        """.trimIndent())
        val deadline = System.currentTimeMillis() + 60_000
        while (System.currentTimeMillis() < deadline) {
            val result = evaluate(instrumentation, webView, "window.__zipProbeResult || ''")
            if (result.startsWith("OK:") || result.startsWith("ERR:")) return result
            Thread.sleep(200)
        }
        return "TIMEOUT"
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findWebView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun evaluate(instrumentation: android.app.Instrumentation, webView: WebView, script: String): String {
        val latch = CountDownLatch(1)
        val answer = AtomicReference("")
        instrumentation.runOnMainSync {
            webView.evaluateJavascript(script) { value ->
                answer.set((JSONTokener(value).nextValue() as? String).orEmpty())
                latch.countDown()
            }
        }
        assertTrue("WebView JavaScript callback timed out", latch.await(10, TimeUnit.SECONDS))
        return answer.get()
    }
}
