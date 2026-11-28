// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.app.Instrumentation
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

internal object DeviceTestHelpers {
    fun decodeUrl(name: String): String {
        val encoded = InstrumentationRegistry.getArguments().getString(name)
        assertTrue("Pass $name instrumentation argument", !encoded.isNullOrBlank())
        return String(Base64.decode(encoded!!, Base64.DEFAULT), Charsets.UTF_8)
    }

    fun openMainWebView(instrumentation: Instrumentation): Pair<MainActivity, WebView> {
        // Warm Android's Charset cache before native libraries load so
        // androidx.test's TestExecutor.toString("UTF_8") does not fail on API 29.
        java.nio.charset.Charset.forName("UTF_8")
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        ) as MainActivity
        val view = awaitWebView(instrumentation, activity)
        awaitBridge(instrumentation, view)
        return activity to view
    }

    fun awaitWebView(instrumentation: Instrumentation, activity: Activity): WebView {
        val deadline = SystemClock.elapsedRealtime() + 45_000
        var webView: WebView? = null
        while (webView == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
            if (webView == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView did not appear", webView != null)
        return webView!!
    }

    fun awaitBridge(instrumentation: Instrumentation, webView: WebView) {
        val deadline = SystemClock.elapsedRealtime() + 45_000
        while (
            SystemClock.elapsedRealtime() < deadline &&
            evaluate(instrumentation, webView, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
        ) {
            Thread.sleep(100)
        }
        assertEquals(
            "Tauri invoke bridge did not load",
            "function",
            evaluate(instrumentation, webView, "typeof window.__TAURI_INTERNALS__?.invoke"),
        )
    }

    fun invoke(
        instrumentation: Instrumentation,
        view: WebView,
        command: String,
        args: JSONObject = JSONObject(),
        timeoutMs: Long = 30_000,
    ): String {
        val key = "__zownload5b_${UUID.randomUUID().toString().replace("-", "")}"
        val keyJs = JSONObject.quote(key)
        val script = """
            window[$keyJs] = '';
            window.__TAURI_INTERNALS__.invoke(${JSONObject.quote(command)}, $args)
              .then(value => window[$keyJs] = 'OK:' + JSON.stringify(value),
                    error => window[$keyJs] = 'ERR:' + (typeof error === 'object' ? JSON.stringify(error) : String(error)));
        """.trimIndent()
        evaluate(instrumentation, view, script)
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        var result = ""
        while (SystemClock.elapsedRealtime() < deadline) {
            result = evaluate(instrumentation, view, "window[$keyJs] || ''")
            if (result.startsWith("OK:") || result.startsWith("ERR:")) break
            Thread.sleep(80)
        }
        if (result.startsWith("ERR:")) {
            throw AssertionError("Tauri command $command failed: ${result.removePrefix("ERR:")}")
        }
        assertTrue("Tauri command $command timed out", result.startsWith("OK:"))
        return result.removePrefix("OK:")
    }

    fun evaluate(instrumentation: Instrumentation, view: WebView, script: String): String {
        val latch = CountDownLatch(1)
        val answer = AtomicReference("")
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) { value ->
                answer.set((JSONTokener(value).nextValue() as? String).orEmpty())
                latch.countDown()
            }
        }
        assertTrue("WebView JavaScript callback timed out", latch.await(15, TimeUnit.SECONDS))
        return answer.get()
    }

    fun queue(instrumentation: Instrumentation, view: WebView): List<JSONObject> =
        JSONArray(invoke(instrumentation, view, "get_queue")).objects()

    fun history(instrumentation: Instrumentation, view: WebView): List<JSONObject> =
        JSONArray(invoke(instrumentation, view, "get_history")).objects()

    fun maxHistoryId(rows: List<JSONObject>): Long = rows.maxOfOrNull { it.optLong("id", 0L) } ?: 0L

    fun enqueue(
        instrumentation: Instrumentation,
        view: WebView,
        url: String,
        format: String,
        quality: JSONObject,
        isPlaylist: Boolean,
    ): String {
        val request = JSONObject()
            .put("url", url)
            .put("format", format)
            .put("quality", quality)
            .put("isPlaylist", isPlaylist)
        val encoded = JSONTokener(
            invoke(instrumentation, view, "enqueue_download", JSONObject().put("request", request))
        ).nextValue()
        assertTrue("enqueue_download did not return an id", encoded is String && encoded.isNotBlank())
        return encoded as String
    }

    fun findPartFile(cacheDir: File, operationId: String): File? =
        File(cacheDir, "zownload-engine/$operationId")
            .listFiles()
            ?.firstOrNull { it.isFile && it.name.endsWith(".part", ignoreCase = true) }

    fun prefixSha256(file: File, bytes: Int = 8192): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(bytes)
            val read = input.read(buf)
            assertTrue("Cannot read prefix from ${file.name}", read > 0)
            digest.update(buf, 0, read)
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    fun descendants(instrumentation: Instrumentation, parentPid: Int): Set<Int> {
        val descriptor = instrumentation.uiAutomation.executeShellCommand("ps -A -o PID,PPID,NAME")
        val report = ParcelFileDescriptor.AutoCloseInputStream(descriptor)
            .bufferedReader().use { it.readText() }
        val relations = report.lineSequence().mapNotNull { line ->
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size < 3) null else {
                val pid = fields[0].toIntOrNull()
                val ppid = fields[1].toIntOrNull()
                if (pid == null || ppid == null) null else pid to ppid
            }
        }.toList()
        val result = mutableSetOf<Int>()
        var frontier = setOf(parentPid)
        while (frontier.isNotEmpty()) {
            val next = relations.filter { it.second in frontier }.map { it.first }.toSet() - result
            result.addAll(next)
            frontier = next
        }
        return result
    }

    fun findDownloadsByTitlePrefix(context: Context, prefix: String): List<Uri> {
        val uris = mutableListOf<Uri>()
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME),
            "${MediaStore.Downloads.DISPLAY_NAME} LIKE ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
            arrayOf("$prefix%", "${Environment.DIRECTORY_DOWNLOADS}/"),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                uris += Uri.withAppendedPath(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id.toString())
            }
        }
        return uris
    }

    fun deleteDownloadsByPrefix(context: Context, prefix: String) {
        findDownloadsByTitlePrefix(context, prefix).forEach { uri ->
            context.contentResolver.delete(uri, null, null)
        }
    }

    fun activeDownloadNotification(context: Context): android.service.notification.StatusBarNotification? =
        context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .firstOrNull { it.id == DownloadForegroundService.NOTIFICATION_ID }

    data class SqliteQueueSnapshot(val status: String, val percent: Double)

    fun readSqliteQueueStatus(context: Context, id: String): String? =
        readSqliteQueueSnapshot(context, id)?.status

    fun readSqliteQueueSnapshot(context: Context, id: String): SqliteQueueSnapshot? {
        val candidates = listOf(
            File(context.filesDir, "zownload.sqlite3"),
            File(context.dataDir, "zownload.sqlite3"),
        )
        val dbFile = candidates.firstOrNull { it.isFile } ?: return null
        return try {
            SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT status, progress FROM queue_items WHERE id = ?", arrayOf(id)).use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val status = cursor.getString(0)
                    val progress = JSONObject(cursor.getString(1))
                    val percent = if (progress.has("percent")) {
                        progress.optDouble("percent", 0.0)
                    } else {
                        progress.optDouble("currentPercent", 0.0)
                    }
                    SqliteQueueSnapshot(status, percent)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findWebView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}
