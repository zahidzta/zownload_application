// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Intent
import android.util.Base64
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
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class YoutubeMp3DeviceTest {
    @Test
    fun tauriRustKotlinPublishesRealYoutubeMp3() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved YouTube URL as youtubeUrlB64", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        assertTrue(url.startsWith("https://www.youtube.com/watch?v=") || url.startsWith("https://youtu.be/"))
        val intent = Intent(instrumentation.targetContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val activity = instrumentation.startActivitySync(intent)
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
            val script = """
                window.__zownloadProbeResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => { window.__zownloadProbeResult = 'OK:' + id; },
                        error => { window.__zownloadProbeResult = 'ERR:' + String(error); });
            """.trimIndent()
            evaluate(instrumentation, view, script, 300)
            val resultDeadline = System.currentTimeMillis() + 300_000
            var result = ""
            while (System.currentTimeMillis() < resultDeadline) {
                result = evaluate(instrumentation, view, "window.__zownloadProbeResult || ''")
                if (result.startsWith("OK:") || result.startsWith("ERR:")) break
                Thread.sleep(500)
            }
            Log.i("Zownload0C06", "TAURI_RESULT $result")
            assertTrue("Tauri → Rust → Kotlin download failed or timed out: $result", result.startsWith("OK:"))
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
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

    private fun evaluate(
        instrumentation: android.app.Instrumentation,
        webView: WebView,
        script: String,
        timeoutSeconds: Long = 10,
    ): String {
        val latch = CountDownLatch(1)
        val answer = AtomicReference("")
        instrumentation.runOnMainSync {
            webView.evaluateJavascript(script) { value ->
                answer.set((JSONTokener(value).nextValue() as? String).orEmpty())
                latch.countDown()
            }
        }
        assertTrue("WebView JavaScript callback timed out", latch.await(timeoutSeconds, TimeUnit.SECONDS))
        return answer.get()
    }
}
