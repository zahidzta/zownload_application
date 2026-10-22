// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ForegroundTimeoutDeviceTest {
    private data class Snapshot(val id: String, val status: String, val percent: Double)

    @Test
    fun timeoutPausesRustAndPreservesPartialMedia() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved long YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        val context = instrumentation.targetContext
        val notifications = context.getSystemService(NotificationManager::class.java)
        AndroidSpikePlugin.testRateLimit = "32K"
        try {
            val activity = instrumentation.startActivitySync(
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            val view = awaitWebView(instrumentation, activity.window.decorView)
            evaluate(instrumentation, view, """
                window.__zownloadTimeoutResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => { window.__zownloadTimeoutResult = 'OK:' + id; },
                        error => { window.__zownloadTimeoutResult = 'ERR:' + String(error); });
            """.trimIndent())
            val deadline = SystemClock.elapsedRealtime() + 120_000
            var active: Snapshot? = null
            var part: File? = null
            while (SystemClock.elapsedRealtime() < deadline) {
                val item = readQueue(instrumentation, view)
                val candidate = File(context.cacheDir, "zownload-0c-06/${item?.id}")
                    .listFiles()?.firstOrNull { it.name.endsWith(".part") && it.length() >= 8192 }
                if (item?.status == "downloading" && candidate != null &&
                    notifications.activeNotifications.any { it.id == 108 } &&
                    descendants(instrumentation, Process.myPid()).isNotEmpty()) {
                    active = item
                    part = candidate
                    break
                }
                val result = evaluate(instrumentation, view, "window.__zownloadTimeoutResult || ''")
                assertTrue("Job failed before timeout: $result", !result.startsWith("ERR:"))
                Thread.sleep(500)
            }
            assertTrue("Need an active job, notification, engine and .part", active != null && part != null)
            val before = active!!
            val partial = part!!
            val bytes = partial.length()
            val prefix = prefixSha256(partial)
            Log.i("Zownload0C15", "TIMEOUT_ACTIVE item=${before.id} percent=${before.percent} bytes=$bytes prefix=$prefix pid=${Process.myPid()}")
            instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_HOME").close()

            val timeoutDeadline = SystemClock.elapsedRealtime() + 90_000
            var paused: Snapshot? = null
            while (SystemClock.elapsedRealtime() < timeoutDeadline) {
                val current = readSnapshot(context.dataDir)
                val notice = notifications.activeNotifications.firstOrNull { it.id == 108 }
                val text = notice?.notification?.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                if (current?.id == before.id && current.status == "paused" &&
                    text == "Downloads paused. Open Zownload to continue." &&
                    descendants(instrumentation, Process.myPid()).isEmpty() &&
                    partial.isFile && partial.length() >= bytes) {
                    paused = current
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Timeout did not pause SQLite, stop engine and explain notification", paused != null)
            val checkpoint = paused!!
            Thread.sleep(2_000)
            assertTrue("Partial transfer changed after timeout", partial.length() >= bytes &&
                prefixSha256(partial) == prefix)
            Log.i("Zownload0C15", "TIMEOUT_PAUSED item=${checkpoint.id} percent=${checkpoint.percent} bytes=${partial.length()} prefix=$prefix notice=paused")

            // The task already has a MainActivity. Launching with CLEAR_TOP and
            // SINGLE_TOP brings that same task forward; startActivitySync waits
            // for a new Activity and would time out when Android reuses it.
            val launch = instrumentation.uiAutomation.executeShellCommand(
                "am start -n com.zownload.app/.MainActivity -f 0x34000000"
            )
            val launchResult = ParcelFileDescriptor.AutoCloseInputStream(launch)
                .bufferedReader().use { it.readText() }
            assertTrue("Could not reopen app: $launchResult", launchResult.contains("Starting:"))
            val restored = readQueue(instrumentation, view)
            assertTrue("Reopened get_queue lost the paused item", restored != null &&
                restored.id == before.id && restored.status == "paused" &&
                restored.percent == checkpoint.percent)
            Log.i("Zownload0C15", "TIMEOUT_REOPENED item=${restored!!.id} percent=${restored.percent} pid=${Process.myPid()}")
        } finally {
            AndroidSpikePlugin.testRateLimit = null
        }
    }

    private fun readSnapshot(dataDir: File): Snapshot? {
        val file = File(dataDir, "android-spike-queue.sqlite3")
        if (!file.isFile) return null
        try {
            SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.rawQuery("SELECT snapshot FROM android_spike_queue WHERE slot = 1", null).use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val json = JSONObject(cursor.getString(0))
                    return Snapshot(json.getString("id"), json.getString("status"),
                        json.getJSONObject("progress").getDouble("percent"))
                }
            }
        } catch (_: android.database.sqlite.SQLiteException) {
            return null
        }
    }

    private fun readQueue(instrumentation: android.app.Instrumentation, view: WebView): Snapshot? {
        evaluate(instrumentation, view,
            "window.__zownloadTimeoutQueue = ''; window.__TAURI_INTERNALS__.invoke('get_queue').then(q => window.__zownloadTimeoutQueue = JSON.stringify(q)); 'requested'")
        val deadline = SystemClock.elapsedRealtime() + 3_000
        var json = ""
        while (SystemClock.elapsedRealtime() < deadline) {
            json = evaluate(instrumentation, view, "window.__zownloadTimeoutQueue || ''")
            if (json.isNotEmpty()) break
            Thread.sleep(50)
        }
        if (json.isEmpty()) return null
        val items = JSONArray(json)
        if (items.length() == 0) return null
        val item = items.getJSONObject(0)
        return Snapshot(item.getString("id"), item.getString("status"),
            item.getJSONObject("progress").getDouble("percent"))
    }

    private fun descendants(instrumentation: android.app.Instrumentation, parent: Int): Set<Int> {
        val descriptor = instrumentation.uiAutomation.executeShellCommand("ps -A -o PID,PPID,NAME")
        val report = ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
        val relations = report.lineSequence().mapNotNull { line ->
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size < 3) null else {
                val pid = fields[0].toIntOrNull()
                val ppid = fields[1].toIntOrNull()
                if (pid == null || ppid == null) null else pid to ppid
            }
        }.toList()
        val result = mutableSetOf<Int>()
        var frontier = setOf(parent)
        while (frontier.isNotEmpty()) {
            val next = relations.filter { it.second in frontier }.map { it.first }.toSet() - result
            result.addAll(next)
            frontier = next
        }
        return result
    }

    private fun prefixSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream -> digest.update(stream.readNBytes(8192)) }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun awaitWebView(instrumentation: android.app.Instrumentation, root: View): WebView {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var view: WebView? = null
        while (view == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { view = findWebView(root) }
            if (view == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView missing", view != null)
        while (SystemClock.elapsedRealtime() < deadline &&
            evaluate(instrumentation, view!!, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
        ) Thread.sleep(100)
        assertTrue("Tauri invoke bridge missing",
            evaluate(instrumentation, view!!, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")
        return view!!
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
