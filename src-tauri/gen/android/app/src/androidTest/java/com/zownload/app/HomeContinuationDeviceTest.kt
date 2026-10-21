// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.NotificationManager
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith
import org.junit.Test

@RunWith(AndroidJUnit4::class)
class HomeContinuationDeviceTest {
    private data class Snapshot(val id: String, val status: String, val percent: Double)

    @Test
    fun rustQueueAndEngineAdvanceForThreeMinutesAfterHome() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved long YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        val context = instrumentation.targetContext
        AndroidSpikePlugin.testRateLimit = "32K"
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        try {
            val viewDeadline = SystemClock.elapsedRealtime() + 30_000
            var webView: WebView? = null
            while (webView == null && SystemClock.elapsedRealtime() < viewDeadline) {
                instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
                if (webView == null) Thread.sleep(100)
            }
            assertTrue("Tauri WebView missing", webView != null)
            val view = webView!!
            while (SystemClock.elapsedRealtime() < viewDeadline &&
                evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
            ) Thread.sleep(100)
            assertTrue("Tauri invoke bridge missing",
                evaluate(instrumentation, view, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")

            evaluate(instrumentation, view, """
                window.__zownloadHomeResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => { window.__zownloadHomeResult = 'OK:' + id; },
                        error => { window.__zownloadHomeResult = 'ERR:' + String(error); });
            """.trimIndent())
            val manager = context.getSystemService(NotificationManager::class.java)
            val startDeadline = SystemClock.elapsedRealtime() + 120_000
            var start: Snapshot? = null
            while (SystemClock.elapsedRealtime() < startDeadline) {
                val item = readSnapshot(context.dataDir)
                if (item?.status == "downloading" && manager.activeNotifications.any { it.id == 108 }) {
                    start = item
                    break
                }
                val result = evaluate(instrumentation, view, "window.__zownloadHomeResult || ''")
                assertTrue("Job failed before Home: $result", !result.startsWith("ERR:"))
                Thread.sleep(500)
            }
            assertTrue("Rust job and service were not active before Home", start != null)
            val first = start!!
            val homeAt = Instant.now()
            instrumentation.uiAutomation.executeShellCommand("input keyevent 3").close()
            var background = false
            val homeDeadline = SystemClock.elapsedRealtime() + 10_000
            while (SystemClock.elapsedRealtime() < homeDeadline) {
                instrumentation.runOnMainSync { background = !activity.hasWindowFocus() }
                if (background) break
                Thread.sleep(100)
            }
            assertTrue("Home did not move the Activity out of focus", background)
            Log.i("Zownload0C09", "HOME_PRESSED at=$homeAt item=${first.id} percent=${first.percent}")

            val began = SystemClock.elapsedRealtime()
            var previous = first.percent
            var changes = 0
            var samples = 0
            while (SystemClock.elapsedRealtime() - began < 180_000) {
                val item = readSnapshot(context.dataDir)
                assertTrue("Queue item disappeared after Home", item != null && item.id == first.id)
                assertTrue("Job stopped after Home: ${item!!.status}", item.status == "downloading")
                assertTrue("Durable progress decreased", item.percent >= previous)
                assertTrue("Activity returned to foreground after Home", !activity.hasWindowFocus())
                assertTrue("Foreground notification vanished after Home",
                    manager.activeNotifications.any { it.id == 108 })
                if (item.percent > previous) changes++
                previous = item.percent
                samples++
                Log.i("Zownload0C09", "HOME_SAMPLE at=${Instant.now()} item=${item.id} status=${item.status} percent=${item.percent} notification=true")
                if (samples == 9) {
                    // Capture Home and the notification icon without opening
                    // the shade, which can bring this Activity back to front.
                    instrumentation.uiAutomation.executeShellCommand("screencap -p /sdcard/zownload-0c09-home.png").close()
                    assertTrue("Screenshot changed foreground Activity", !activity.hasWindowFocus())
                    Log.i("Zownload0C09", "HOME_SCREENSHOT /sdcard/zownload-0c09-home.png")
                }
                Thread.sleep(15_000)
            }
            val elapsed = SystemClock.elapsedRealtime() - began
            assertTrue("No durable progress change after Home", changes >= 2 && previous > first.percent)
            Log.i("Zownload0C09", "HOME_TEST_OK start=$homeAt end=${Instant.now()} elapsedMs=$elapsed item=${first.id} startPercent=${first.percent} endPercent=$previous changes=$changes samples=$samples notification=true home=true")
        } finally {
            AndroidSpikePlugin.testRateLimit = null
        }
    }

    private fun readSnapshot(dataDir: File): Snapshot? {
        val file = File(dataDir, "android-spike-queue.sqlite3")
        if (!file.isFile) return null
        // SQLite may need to recover a rollback journal while Rust is alive.
        // This test issues SELECT only; Rust remains the sole queue writer.
        SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.rawQuery("SELECT snapshot FROM android_spike_queue WHERE slot = 1", null).use { cursor ->
                if (!cursor.moveToFirst()) return null
                val json = JSONObject(cursor.getString(0))
                return Snapshot(json.getString("id"), json.getString("status"),
                    json.getJSONObject("progress").getDouble("percent"))
            }
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
