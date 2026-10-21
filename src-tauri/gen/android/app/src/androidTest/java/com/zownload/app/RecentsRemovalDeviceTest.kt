// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.ActivityManager
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
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.runner.RunWith
import org.junit.Test

@RunWith(AndroidJUnit4::class)
class RecentsRemovalDeviceTest {
    private data class Snapshot(val id: String, val status: String, val percent: Double)

    @Test
    fun removingTaskPausesRustAndStopsEngineAndService() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved long YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        val context = instrumentation.targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        AndroidSpikePlugin.testRateLimit = "32K"
        try {
            val activity = instrumentation.startActivitySync(
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            val webView = awaitWebView(instrumentation, activity)
            evaluate(instrumentation, webView, """
                window.__zownloadRecentsResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => { window.__zownloadRecentsResult = 'OK:' + id; },
                        error => { window.__zownloadRecentsResult = 'ERR:' + String(error); });
            """.trimIndent())
            val deadline = SystemClock.elapsedRealtime() + 120_000
            var before: Snapshot? = null
            var children = emptySet<Int>()
            while (SystemClock.elapsedRealtime() < deadline) {
                val item = readQueue(instrumentation, webView)
                val active = manager.activeNotifications.any { it.id == 108 }
                val pids = descendants(instrumentation, Process.myPid())
                val bytes = privateBytes(context.cacheDir)
                if (item?.status == "downloading" && active && pids.isNotEmpty() && bytes > 0) {
                    before = item
                    children = pids
                    break
                }
                val result = evaluate(instrumentation, webView, "window.__zownloadRecentsResult || ''")
                assertTrue("Job failed before task removal: $result", !result.startsWith("ERR:"))
                Thread.sleep(500)
            }
            assertTrue("Need an active Rust job, notification, child process and partial media", before != null)
            val first = before!!
            val bytesBefore = privateBytes(context.cacheDir)
            val removedAt = Instant.now()
            val appTask = context.getSystemService(ActivityManager::class.java).appTasks
                .firstOrNull { it.taskInfo.baseActivity?.packageName == context.packageName }
            assertTrue("App task missing from recents", appTask != null)
            // This Android API performs the same task removal as a recents swipe.
            Log.i("Zownload0C10", "RECENTS_REMOVING at=$removedAt item=${first.id} percent=${first.percent} children=$children bytes=$bytesBefore")
            appTask!!.finishAndRemoveTask()
            // Tauri exits the process when its only Activity is destroyed.
            // The host checks cancellation and runs reopenedQueueIsPaused in
            // a fresh instrumentation process after this removal.
        } finally {
            AndroidSpikePlugin.testRateLimit = null
        }
    }

    @Test
    fun reopenedQueueIsPaused() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        val view = awaitWebView(instrumentation, activity)
        val started = evaluate(instrumentation, view,
            "window.__TAURI_INTERNALS__.invoke('get_queue').then(q => window.__zownloadQueue = JSON.stringify(q)); 'started'")
        assertTrue("Reopen did not invoke get_queue", started == "started")
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var queue = ""
        while (SystemClock.elapsedRealtime() < deadline) {
            queue = evaluate(instrumentation, view, "window.__zownloadQueue || ''")
            if (queue.isNotEmpty()) break
            Thread.sleep(100)
        }
        val items = JSONArray(queue)
        assertTrue("Reopened queue did not contain one item", items.length() == 1)
        val item = items.getJSONObject(0)
        val snapshot = readSnapshot(context.dataDir)
        assertTrue("Reopened queue lost paused item", item.getString("status") == "paused" &&
            snapshot?.status == "paused" && item.getString("id") == snapshot.id)
        Log.i("Zownload0C10", "REOPENED_PAUSED item=${item.getString("id")} percent=${snapshot!!.percent}")
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
            // Rust can still be creating the database/journal at first launch.
            // The caller retries; SQLite remains owned and written by Rust.
            return null
        }
    }

    private fun readQueue(instrumentation: android.app.Instrumentation, view: WebView): Snapshot? {
        evaluate(instrumentation, view,
            "window.__zownloadActiveQueue = ''; window.__TAURI_INTERNALS__.invoke('get_queue').then(q => window.__zownloadActiveQueue = JSON.stringify(q)); 'requested'")
        val deadline = SystemClock.elapsedRealtime() + 3_000
        var json = ""
        while (SystemClock.elapsedRealtime() < deadline) {
            json = evaluate(instrumentation, view, "window.__zownloadActiveQueue || ''")
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

    private fun privateBytes(cacheDir: File): Long = File(cacheDir, "zownload-0c-06")
        .walkTopDown().filter { it.isFile }.sumOf { it.length() }

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

    private fun awaitWebView(instrumentation: android.app.Instrumentation, activity: android.app.Activity): WebView {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var webView: WebView? = null
        while (webView == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
            if (webView == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView missing", webView != null)
        while (SystemClock.elapsedRealtime() < deadline &&
            evaluate(instrumentation, webView!!, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
        ) Thread.sleep(100)
        assertTrue("Tauri invoke bridge missing",
            evaluate(instrumentation, webView!!, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")
        return webView!!
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
