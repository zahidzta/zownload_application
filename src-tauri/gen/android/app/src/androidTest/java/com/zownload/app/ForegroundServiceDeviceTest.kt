// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.NotificationManager
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
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith
import org.junit.Test

@RunWith(AndroidJUnit4::class)
class ForegroundServiceDeviceTest {
    @Test
    fun rustWorkShowsAndStopsDataSyncNotification() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass approved YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        try {
            val viewDeadline = System.currentTimeMillis() + 30_000
            var webView: WebView? = null
            while (webView == null && System.currentTimeMillis() < viewDeadline) {
                instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
                if (webView == null) Thread.sleep(100)
            }
            assertTrue("Tauri WebView missing", webView != null)
            val view = webView!!
            while (System.currentTimeMillis() < viewDeadline &&
                evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
            ) Thread.sleep(100)
            assertTrue("Tauri invoke bridge missing",
                evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")

            val script = """
                window.__zownloadServiceResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => { window.__zownloadServiceResult = 'OK:' + id; },
                        error => { window.__zownloadServiceResult = 'ERR:' + String(error); });
            """.trimIndent()
            evaluate(instrumentation, view, script)
            val manager = activity.getSystemService(NotificationManager::class.java)
            val deadline = System.currentTimeMillis() + 300_000
            var observed = false
            var result = ""
            while (System.currentTimeMillis() < deadline) {
                if (manager.activeNotifications.any { it.id == 108 }) {
                    if (!observed) Log.i("Zownload0C08", "NOTIFICATION_OBSERVED active=true")
                    observed = true
                }
                result = evaluate(instrumentation, view, "window.__zownloadServiceResult || ''")
                if (result.startsWith("OK:") || result.startsWith("ERR:")) break
                Thread.sleep(100)
            }
            assertTrue("No active dataSync notification was observed", observed)
            assertTrue("Rust work failed: $result", result.startsWith("OK:"))
            val stopDeadline = System.currentTimeMillis() + 10_000
            while (manager.activeNotifications.any { it.id == 108 } && System.currentTimeMillis() < stopDeadline) {
                Thread.sleep(100)
            }
            assertTrue("Foreground notification remained after Rust work",
                manager.activeNotifications.none { it.id == 108 })
            Log.i("Zownload0C08", "SERVICE_TEST_OK result=$result notificationStopped=true")
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            findWebView(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun evaluate(instrumentation: android.app.Instrumentation, view: WebView, script: String): String {
        val latch = CountDownLatch(1)
        val answer = AtomicReference("")
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) { value ->
                answer.set((JSONTokener(value).nextValue() as? String).orEmpty())
                latch.countDown()
            }
        }
        assertTrue("WebView callback timed out", latch.await(10, TimeUnit.SECONDS))
        return answer.get()
    }
}
