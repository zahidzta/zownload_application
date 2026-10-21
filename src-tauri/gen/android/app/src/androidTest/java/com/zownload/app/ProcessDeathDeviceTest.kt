// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Instrumentation
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
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
class ProcessDeathDeviceTest {
    @Test
    fun startAndLeavePartForHostKill() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved long YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        AndroidSpikePlugin.testRateLimit = "32K"
        val view = openView(instrumentation)
        evaluate(instrumentation, view, """
            window.__zownloadDeathResult = '';
            window.__TAURI_INTERNALS__.invoke('enqueue_download', {
              request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
            }).then(id => { window.__zownloadDeathResult = 'OK:' + id; },
                    error => { window.__zownloadDeathResult = 'ERR:' + String(error); });
        """.trimIndent())
        val deadline = SystemClock.elapsedRealtime() + 120_000
        while (SystemClock.elapsedRealtime() < deadline) {
            val item = queue(instrumentation, view)
            val part = item?.let { partial(context.cacheDir, it.getString("id")) }
            if (item?.getString("status") == "downloading" && part != null && part.length() >= 8192) {
                Log.i("Zownload0C11", "PREKILL pid=${Process.myPid()} item=${item.getString("id")} " +
                    "part=${part.name} bytes=${part.length()} prefix=${prefixHash(part)}")
                // The host kills this process while instrumentation is still
                // active. Returning here would let the runner end the process.
                Thread.sleep(180_000)
                return
            }
            val result = evaluate(instrumentation, view, "window.__zownloadDeathResult || ''")
            assertTrue("Download failed before process kill: $result", !result.startsWith("ERR:"))
            Thread.sleep(500)
        }
        throw AssertionError("No active download with a nonempty .part file")
    }

    @Test
    fun reopenAndContinueSavedPart() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val view = openView(instrumentation)
        val item = queue(instrumentation, view) ?: throw AssertionError("Reopened queue is empty")
        assertTrue("Interrupted item did not restore as paused", item.getString("status") == "paused")
        val id = item.getString("id")
        val part = partial(context.cacheDir, id) ?: throw AssertionError("Saved .part is missing")
        val startingBytes = part.length()
        val startingHash = prefixHash(part)
        assertTrue("Saved .part is empty", startingBytes >= 8192)
        val diskStatus = SQLiteDatabase.openDatabase(
            File(context.dataDir, "android-spike-queue.sqlite3").absolutePath,
            null, SQLiteDatabase.OPEN_READONLY,
        ).use { db ->
            db.rawQuery("SELECT snapshot FROM android_spike_queue WHERE slot = 1", null).use { cursor ->
                assertTrue("Rust queue row is missing", cursor.moveToFirst())
                JSONObject(cursor.getString(0)).getString("status")
            }
        }
        assertTrue("SQLite did not contain paused", diskStatus == "paused")
        Thread.sleep(5000)
        val stillPaused = queue(instrumentation, view)
        assertTrue("Queue resumed without Continue", stillPaused?.getString("status") == "paused")
        assertTrue("Bytes changed before Continue", part.length() == startingBytes)
        Log.i("Zownload0C11", "REOPENED_PAUSED item=$id bytes=$startingBytes prefix=$startingHash idleMs=5000")

        AndroidSpikePlugin.testRateLimit = "256K"
        evaluate(instrumentation, view, """
            window.__zownloadContinueResult = '';
            window.__TAURI_INTERNALS__.invoke('resume_download', {id: ${JSONObject.quote(id)}})
              .then(() => { window.__zownloadContinueResult = 'OK'; },
                    error => { window.__zownloadContinueResult = 'ERR:' + String(error); });
        """.trimIndent())
        val deadline = SystemClock.elapsedRealtime() + 120_000
        while (SystemClock.elapsedRealtime() < deadline) {
            val now = partial(context.cacheDir, id)
            if (now != null && now.length() > startingBytes + 8192) {
                val continuedHash = prefixHash(now)
                assertTrue("Saved prefix changed during Continue", continuedHash == startingHash)
                Log.i("Zownload0C11", "CONTINUED_PART item=$id before=$startingBytes " +
                    "after=${now.length()} prefix=$continuedHash")
                return
            }
            val result = evaluate(instrumentation, view, "window.__zownloadContinueResult || ''")
            assertTrue("Continue failed: $result", !result.startsWith("ERR:"))
            Thread.sleep(500)
        }
        throw AssertionError("Saved .part did not grow after Continue")
    }

    private fun partial(cache: File, id: String): File? = File(cache, "zownload-0c-06/$id")
        .listFiles()?.firstOrNull { it.name.endsWith(".part") }

    private fun prefixHash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val prefix = ByteArray(8192)
            val count = input.read(prefix)
            assertTrue("Cannot read .part prefix", count == prefix.size)
            digest.update(prefix)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun queue(instrumentation: Instrumentation, view: WebView): JSONObject? {
        evaluate(instrumentation, view,
            "window.__zownloadQueue = ''; window.__TAURI_INTERNALS__.invoke('get_queue').then(q => window.__zownloadQueue = JSON.stringify(q)); 'requested'")
        val deadline = SystemClock.elapsedRealtime() + 3000
        while (SystemClock.elapsedRealtime() < deadline) {
            val answer = evaluate(instrumentation, view, "window.__zownloadQueue || ''")
            if (answer.isNotEmpty()) {
                val items = JSONArray(answer)
                return if (items.length() == 0) null else items.getJSONObject(0)
            }
            Thread.sleep(50)
        }
        return null
    }

    private fun openView(instrumentation: Instrumentation): WebView {
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var webView: WebView? = null
        while (webView == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { webView = findView(activity.window.decorView) }
            if (webView == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView missing", webView != null)
        while (SystemClock.elapsedRealtime() < deadline &&
            evaluate(instrumentation, webView!!, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
        ) Thread.sleep(100)
        assertTrue("Tauri bridge missing",
            evaluate(instrumentation, webView!!, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")
        return webView!!
    }

    private fun findView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            findView(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun evaluate(instrumentation: Instrumentation, view: WebView, script: String): String {
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
