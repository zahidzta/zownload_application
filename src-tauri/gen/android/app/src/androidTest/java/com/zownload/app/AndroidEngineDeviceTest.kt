// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidEngineDeviceTest {
    private data class DownloadReport(
        val id: String,
        val title: String,
        val files: List<File>,
        val maxProgress: Double,
        val maxTotal: Int,
        val sawDownloading: Boolean,
    )

    @Test
    fun removesKnownInterruptedQueueItem() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        val id = args.getString("cleanupQueueId")
        assertTrue("Pass the exact interrupted queue id", !id.isNullOrBlank())
        val url = decodeUrl(args.getString("cleanupUrlB64"), "cleanupUrlB64")
        val isPlaylist = args.getString("cleanupIsPlaylist")?.toBooleanStrictOrNull()
            ?: throw AssertionError("Pass whether the interrupted item is a playlist")

        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        ) as MainActivity
        try {
            val view = awaitWebView(instrumentation, activity)
            awaitBridge(instrumentation, view)
            val item = queue(view).objects().firstOrNull { it.optString("id") == id }
                ?: throw AssertionError("The exact interrupted queue item $id is no longer present")
            val request = item.optJSONObject("request") ?: throw AssertionError("Interrupted item has no request")
            assertEquals("Refusing to remove a queue item from another fixture", url, request.optString("url"))
            assertEquals("Refusing to remove a queue item with another request type", isPlaylist, request.optBoolean("isPlaylist"))
            assertEquals("Interrupted playlist should reopen paused", "paused", item.optString("status"))

            invoke(view, "remove_download", JSONObject().put("id", id))
            awaitQueueRemoval(view, id!!, 30_000)
            Log.i(TAG, "RECOVERY_REMOVED id=$id playlist=$isPlaylist via=remove_download queueEmpty=${queue(view).length() == 0}")
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun productionEngineRunsSingleMp3Mp4PlaylistAndQueueLifecycle() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        val mp3Url = decodeUrl(args.getString("mp3UrlB64"), "mp3UrlB64")
        val mp4Url = decodeUrl(args.getString("mp4UrlB64"), "mp4UrlB64")
        val playlistUrl = decodeUrl(args.getString("playlistUrlB64"), "playlistUrlB64")
        val cancelUrl = decodeUrl(args.getString("cancelUrlB64"), "cancelUrlB64")
        val expectedPlaylistItems = args.getString("playlistItems")?.toIntOrNull() ?: 28
        val priorFailureNotificationId = args.getString("priorFailureNotificationId")
        assertTrue("Playlist fixture must contain at least two locked entries", expectedPlaylistItems >= 2)
        assertYouTubeSingle(mp3Url, "MP3 fixture")
        assertYouTubeSingle(mp4Url, "MP4 fixture")
        assertTrue("Playlist fixture must be a YouTube playlist", playlistUrl.contains("youtube.com/playlist?list="))
        assertYouTubeSingle(cancelUrl, "Cancellation fixture")

        val context = instrumentation.targetContext
        val firstActivity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        ) as MainActivity
        var activeActivity = firstActivity
        var activeView = awaitWebView(instrumentation, activeActivity)
        var originalSettings: JSONObject? = null
        var originalNotificationIds = emptySet<String>()
        var cancellationId: String? = null
        var progressObserved = false
        val recreatedActivity = AtomicReference<MainActivity?>()
        val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) {
                if (activity is MainActivity && activity !== firstActivity) recreatedActivity.set(activity)
            }
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }
        firstActivity.application.registerActivityLifecycleCallbacks(lifecycleCallbacks)

        try {
            awaitBridge(instrumentation, activeView)
            assertEquals("Device proof requires an idle queue; no existing item was changed", 0, queue(activeView).length())

            originalSettings = JSONObject(invoke(activeView, "get_settings", JSONObject()))
            originalNotificationIds = errorNotifications(activeView).objects().map { it.optString("id") }.toSet()
            Log.i(TAG, "SETTINGS_BEFORE zipPlaylists=${originalSettings!!.getBoolean("zipPlaylists")} language=${originalSettings!!.getString("language")}")
            val testSettings = JSONObject(originalSettings.toString()).put("zipPlaylists", false)
            invoke(activeView, "set_settings", JSONObject().put("settings", testSettings))
            val savedSettings = JSONObject(invoke(activeView, "get_settings", JSONObject()))
            assertEquals(testSettings.getString("language"), savedSettings.getString("language"))
            assertEquals(testSettings.getBoolean("zipPlaylists"), savedSettings.getBoolean("zipPlaylists"))
            assertEquals(testSettings.optString("downloadDir"), savedSettings.optString("downloadDir"))
            Log.i(TAG, "SETTINGS_ROUND_TRIP zipPlaylists=${savedSettings.getBoolean("zipPlaylists")} language=${savedSettings.getString("language")}")

            if (!priorFailureNotificationId.isNullOrBlank()) {
                dismissPriorDeviceTestFailure(
                    activeView,
                    "FREE Time Lapse HD stock footage: Sunset in 1080p HD CC-By NatureClip",
                    priorFailureNotificationId,
                )
            }
            Log.i(TAG, "FIXTURES mp3=$mp3Url mp4=$mp4Url playlist=$playlistUrl playlistItems=$expectedPlaylistItems cancel=$cancelUrl")

            val baselineHistoryId = maxHistoryId(history(activeView))
            Log.i(TAG, "PHASE_BEGIN label=single-mp3")
            val mp3 = runSingle(
                context, activeView, mp3Url, "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                expectedExtension = "mp3",
            )
            progressObserved = progressObserved || mp3.sawDownloading

            Log.i(TAG, "PHASE_BEGIN label=single-mp4")
            val mp4 = runSingle(
                context, activeView, mp4Url, "mp4",
                JSONObject().put("type", "video").put("height", 1080),
                expectedExtension = "mp4",
            )
            progressObserved = progressObserved || mp4.sawDownloading

            Log.i(TAG, "PHASE_BEGIN label=playlist-mp3 expectedItems=$expectedPlaylistItems")
            val playlist = runPlaylist(context, activeView, playlistUrl, expectedPlaylistItems)
            progressObserved = progressObserved || playlist.sawDownloading
            assertTrue("Queue emitted no downloading progress state", progressObserved)

            val beforeHistory = history(activeView)
            val beforeMaxHistoryId = maxHistoryId(beforeHistory)
            cancellationId = enqueue(
                activeView,
                cancelUrl,
                "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                isPlaylist = false,
            )
            val active = awaitDownloading(activeView, cancellationId!!, 180_000)
            val activePercent = active.optJSONObject("progress")?.optDouble("percent", 0.0) ?: 0.0
            assertEquals("Single queue item must expose single-file progress", "single", active.getJSONObject("progress").getString("kind"))
            Log.i(TAG, "CANCEL_SETUP item=$cancellationId title=${valueText(active.opt("title"))} percent=$activePercent status=${active.getString("status")}")

            instrumentation.runOnMainSync { firstActivity.recreate() }
            val recreateDeadline = SystemClock.elapsedRealtime() + 30_000
            while (recreatedActivity.get() == null && SystemClock.elapsedRealtime() < recreateDeadline) Thread.sleep(100)
            activeActivity = recreatedActivity.get() ?: throw AssertionError("Activity recreation did not create a new MainActivity")
            activeView = awaitWebView(instrumentation, activeActivity)
            awaitBridge(instrumentation, activeView)

            val restored = awaitQueueItem(activeView, cancellationId!!, 20_000)
            assertEquals("Rust queue item was not retained across WebView recreation", "downloading", restored.getString("status"))
            val restoredProgress = restored.getJSONObject("progress").optDouble("percent", 0.0)
            assertTrue("Restored queue progress moved backwards", restoredProgress >= activePercent)
            val title = valueText(restored.opt("title")).ifBlank {
                restored.optJSONObject("request")?.optString("url", "").orEmpty()
            }
            assertTrue("Restored React UI does not show the shared queue title '$title'", awaitDocumentContains(activeView, title, 20_000))
            Log.i(TAG, "WEBVIEW_RECREATION item=$cancellationId title=$title percent=$restoredProgress sharedQueue=true")

            invoke(activeView, "remove_download", JSONObject().put("id", cancellationId))
            awaitQueueRemoval(activeView, cancellationId!!, 30_000)
            cancellationId = null
            assertTrue("Cancelled item was incorrectly written to history", !hasHistoryRequest(history(activeView), cancelUrl, "mp3", false, beforeMaxHistoryId))
            Log.i(TAG, "CANCELLATION removed=true queueOwnedByRust=true")

            val finalHistory = history(activeView)
            assertTrue("Single MP3 was not persisted to history", hasHistoryRequest(finalHistory, mp3Url, "mp3", false, baselineHistoryId))
            assertTrue("Single MP4 was not persisted to history", hasHistoryRequest(finalHistory, mp4Url, "mp4", false, baselineHistoryId))
            assertTrue("Playlist was not persisted to history", hasHistoryRequest(finalHistory, playlistUrl, "mp3", true, baselineHistoryId))
            assertEquals("Completed test work left entries in Rust's queue", 0, queue(activeView).length())
            Log.i(TAG, "QUEUE_HISTORY mp3=true mp4=true playlist=true cancelled=false queueEmpty=true")

            Log.i(TAG, "PROOF_COMPLETE outputsMp3=${mp3.files.size} outputsMp4=${mp4.files.size} outputsPlaylist=${playlist.files.size} playlistItems=${playlist.maxTotal}")
        } finally {
            cancellationId?.let { id ->
                try {
                    invoke(activeView, "remove_download", JSONObject().put("id", id), 30_000)
                    awaitQueueRemoval(activeView, id, 30_000)
                } catch (error: Exception) {
                    Log.e(TAG, "TEST_CLEANUP_FAILED item=$id", error)
                }
            }
            originalSettings?.let { settings ->
                try { invoke(activeView, "set_settings", JSONObject().put("settings", settings), 30_000) } catch (_: Exception) {}
            }
            try {
                errorNotifications(activeView).objects()
                    .filter { it.optString("id") !in originalNotificationIds }
                    .forEach { invoke(activeView, "dismiss_error_notification", JSONObject().put("id", it.getString("id")), 30_000) }
            } catch (_: Exception) {}
            firstActivity.application.unregisterActivityLifecycleCallbacks(lifecycleCallbacks)
            instrumentation.runOnMainSync { activeActivity.finish() }
            if (activeActivity !== firstActivity) instrumentation.runOnMainSync { firstActivity.finish() }
        }
    }

    private fun runSingle(
        context: Context,
        view: WebView,
        url: String,
        format: String,
        quality: JSONObject,
        expectedExtension: String,
    ): DownloadReport {
        val beforeMaxId = maxHistoryId(history(view))
        val id = enqueue(view, url, format, quality, isPlaylist = false)
        val result = awaitCompletion(view, id, url, format, isPlaylist = false, beforeMaxId = beforeMaxId, timeoutMs = 900_000)
        assertTrue("$format did not report active downloading", result.sawDownloading)
        val output = outputDirectory(context, id)
        val files = outputFiles(output)
        assertEquals("Expected one $format output", 1, files.size)
        val file = files.single()
        assertTrue("$format output is empty", file.length() > 1_000)
        assertEquals("Unexpected output extension", expectedExtension, file.extension.lowercase())
        if (format == "mp4") assertTrue("MP4 output has no ISO BMFF ftyp signature", hasMp4Signature(file))
        val title = historyTitle(history(view), url, format, false)
        val report = DownloadReport(id, title, files, result.maxProgress, result.maxTotal, result.sawDownloading)
        logOutput("single-$format", report)
        return report
    }

    private fun runPlaylist(context: Context, view: WebView, url: String, expectedItems: Int): DownloadReport {
        val beforeMaxId = maxHistoryId(history(view))
        val id = enqueue(view, url, "mp3", JSONObject().put("type", "max"), isPlaylist = true)
        val result = awaitCompletion(view, id, url, "mp3", isPlaylist = true, beforeMaxId = beforeMaxId, timeoutMs = 1_200_000)
        assertTrue("Playlist did not report active downloading", result.sawDownloading)
        assertEquals("Rust queue total differs from the locked playlist size", expectedItems, result.maxTotal)
        val files = outputFiles(outputDirectory(context, id))
        assertTrue("Playlist produced fewer than two audio files", files.size >= 2)
        assertTrue("Playlist returned more output files than the analyzed entry count", files.size <= expectedItems)
        assertTrue("Playlist contains an empty file", files.all { it.length() > 1_000 && it.extension.equals("mp3", true) })
        val title = historyTitle(history(view), url, "mp3", true)
        val report = DownloadReport(id, title, files, result.maxProgress, result.maxTotal, result.sawDownloading)
        logOutput("playlist-mp3", report)
        return report
    }

    private data class Completion(val maxProgress: Double, val maxTotal: Int, val sawDownloading: Boolean)

    private fun awaitCompletion(
        view: WebView,
        id: String,
        url: String,
        format: String,
        isPlaylist: Boolean,
        beforeMaxId: Long,
        timeoutMs: Long,
    ): Completion {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        var maxProgress = 0.0
        var maxTotal = 0
        var sawDownloading = false
        while (SystemClock.elapsedRealtime() < deadline) {
            val item = queue(view).objects().firstOrNull { it.optString("id") == id }
            if (item != null) {
                val status = item.optString("status")
                if (status == "failed") throw AssertionError("Download failed: ${item.optJSONObject("error")}")
                if (status == "downloading" || status == "postProcessing" || status == "packaging") {
                    sawDownloading = true
                    val progress = item.optJSONObject("progress")
                    if (progress != null) {
                        val percent = if (progress.has("percent")) progress.optDouble("percent", 0.0) else progress.optDouble("currentPercent", 0.0)
                        maxProgress = maxOf(maxProgress, percent)
                        maxTotal = maxOf(maxTotal, progress.optInt("total", 0))
                    }
                }
            }
            if (item == null) {
                val notification = errorNotifications(view).objects().firstOrNull { it.optString("id") == id }
                if (notification != null) throw AssertionError("Download failed: ${notification.optJSONObject("error")}")
            }
            if (hasHistoryRequest(history(view), url, format, isPlaylist, beforeMaxId)) {
                assertFalse("Completed item remained in the active queue", queue(view).objects().any { it.optString("id") == id })
                return Completion(maxProgress, maxTotal, sawDownloading)
            }
            Thread.sleep(250)
        }
        throw AssertionError("Timed out waiting for $format completion for $url; item=$id")
    }

    private fun awaitDownloading(view: WebView, id: String, timeoutMs: Long): JSONObject {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            val item = queue(view).objects().firstOrNull { it.optString("id") == id }
            val percent = item?.optJSONObject("progress")?.optDouble("percent", 0.0) ?: 0.0
            if (item != null && item.optString("status") == "downloading" && percent > 0.0) return item
            if (item != null && item.optString("status") == "failed") throw AssertionError("Cancellation fixture failed before download: ${item.optJSONObject("error")}")
            Thread.sleep(250)
        }
        throw AssertionError("Cancellation fixture never reported active download progress")
    }

    private fun awaitQueueItem(view: WebView, id: String, timeoutMs: Long): JSONObject {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            queue(view).objects().firstOrNull { it.optString("id") == id }?.let { return it }
            Thread.sleep(100)
        }
        throw AssertionError("Rust queue did not restore item $id after WebView recreation")
    }

    private fun awaitQueueRemoval(view: WebView, id: String, timeoutMs: Long) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            if (queue(view).objects().none { it.optString("id") == id }) return
            Thread.sleep(150)
        }
        throw AssertionError("Rust did not remove cancelled queue item $id")
    }

    private fun valueText(value: Any?): String = if (value == null || value == JSONObject.NULL) "" else value.toString()

    private fun awaitDocumentContains(view: WebView, text: String, timeoutMs: Long): Boolean {
        if (text.isBlank()) return false
        val encoded = JSONObject.quote(text)
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            val found = evaluate(view, "document.body.innerText.includes($encoded) ? 'yes' : 'no'")
            if (found == "yes") return true
            Thread.sleep(200)
        }
        val body = evaluate(view, "document.body.innerText || ''").replace('\n', ' ').take(600)
        Log.i(TAG, "WEBVIEW_TEXT_MISSING title=$text body=$body")
        return false
    }

    private fun enqueue(view: WebView, url: String, format: String, quality: JSONObject, isPlaylist: Boolean): String {
        Log.i(TAG, "ENQUEUE_BEGIN playlist=$isPlaylist format=$format url=$url")
        val request = JSONObject()
            .put("url", url)
            .put("format", format)
            .put("quality", quality)
            .put("isPlaylist", isPlaylist)
        val encoded = JSONTokener(invoke(view, "enqueue_download", JSONObject().put("request", request), 30_000)).nextValue()
        assertTrue("enqueue_download did not return a queue id", encoded is String && encoded.isNotBlank())
        val id = encoded as String
        Log.i(TAG, "ENQUEUE_ACCEPTED playlist=$isPlaylist id=$id")
        return id
    }

    private fun queue(view: WebView): JSONArray = JSONArray(invoke(view, "get_queue", JSONObject()))

    private fun history(view: WebView): JSONArray = JSONArray(invoke(view, "get_history", JSONObject()))

    private fun errorNotifications(view: WebView): JSONArray = JSONArray(invoke(view, "get_error_notifications", JSONObject()))

    private fun dismissPriorDeviceTestFailure(view: WebView, title: String, id: String) {
        errorNotifications(view).objects()
            .filter { it.optString("id") == id && it.optString("title") == title }
            .filter { it.optJSONObject("error")?.optString("detail") == "ERROR: Postprocessing: Error opening output files: Invalid argument" }
            .forEach { invoke(view, "dismiss_error_notification", JSONObject().put("id", it.getString("id"))) }
    }

    private fun hasHistoryRequest(rows: JSONArray, url: String, format: String, isPlaylist: Boolean, afterId: Long): Boolean =
        rows.objects().any { row ->
            val request = row.optJSONObject("request") ?: return@any false
            row.optLong("id", 0L) > afterId && request.optString("url") == url &&
                request.optString("format") == format && request.optBoolean("isPlaylist") == isPlaylist
        }

    private fun historyTitle(rows: JSONArray, url: String, format: String, isPlaylist: Boolean): String =
        rows.objects().first { row ->
            val request = row.optJSONObject("request") ?: return@first false
            request.optString("url") == url && request.optString("format") == format &&
                request.optBoolean("isPlaylist") == isPlaylist
        }.optString("title")

    private fun maxHistoryId(rows: JSONArray): Long = rows.objects().maxOfOrNull { it.optLong("id", 0L) } ?: 0L

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

    private fun outputDirectory(context: Context, id: String): File {
        val candidates = listOf(
            File(context.filesDir, "android-engine-outputs/$id"),
            File(context.dataDir, "android-engine-outputs/$id"),
        )
        return candidates.firstOrNull { it.isDirectory }
            ?: throw AssertionError("AndroidEngine output directory missing; checked ${candidates.joinToString { it.absolutePath }}")
    }

    private fun outputFiles(directory: File): List<File> =
        directory.listFiles()?.filter { it.isFile && !it.name.endsWith(".part", true) }?.sortedBy { it.name }
            ?: throw AssertionError("Cannot list AndroidEngine outputs at ${directory.absolutePath}")

    private fun hasMp4Signature(file: File): Boolean = FileInputStream(file).use { input ->
        val bytes = ByteArray(12)
        if (input.read(bytes) != bytes.size) return@use false
        String(bytes.copyOfRange(4, 8), Charsets.US_ASCII) == "ftyp"
    }

    private fun logOutput(label: String, report: DownloadReport) {
        val records = report.files.map { file ->
            val hash = sha256(file)
            "${file.name}:${file.length()}:$hash"
        }
        val manifest = records.sorted().joinToString("\n")
        Log.i(TAG, "OUTPUT label=$label id=${report.id} title=${report.title} files=${records.size} maxProgress=${report.maxProgress} manifestSha256=${sha256(manifest.toByteArray())}")
        records.forEach { Log.i(TAG, "OUTPUT_FILE label=$label $it") }
    }

    private fun sha256(file: File): String = FileInputStream(file).use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
        digest.digest().hex()
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).hex()

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    private fun decodeUrl(encoded: String?, name: String): String {
        assertTrue("Pass $name to the device test", !encoded.isNullOrBlank())
        return String(Base64.decode(encoded!!, Base64.DEFAULT), Charsets.UTF_8)
    }

    private fun assertYouTubeSingle(url: String, label: String) {
        assertTrue("$label must use a YouTube single URL", url.startsWith("https://www.youtube.com/watch?v=") || url.startsWith("https://youtu.be/"))
    }

    private fun awaitWebView(instrumentation: android.app.Instrumentation, activity: Activity): WebView {
        val deadline = SystemClock.elapsedRealtime() + 45_000
        var webView: WebView? = null
        while (webView == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { webView = findWebView(activity.window.decorView) }
            if (webView == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView did not appear", webView != null)
        return webView!!
    }

    private fun awaitBridge(instrumentation: android.app.Instrumentation, webView: WebView) {
        val deadline = SystemClock.elapsedRealtime() + 45_000
        while (SystemClock.elapsedRealtime() < deadline &&
            evaluate(webView, "typeof window.__TAURI_INTERNALS__?.invoke") != "function") Thread.sleep(100)
        assertEquals("Tauri invoke bridge did not load", "function", evaluate(webView, "typeof window.__TAURI_INTERNALS__?.invoke"))
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            findWebView(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun invoke(view: WebView, command: String, args: JSONObject, timeoutMs: Long = 30_000): String {
        val key = "__zownload5a09_${UUID.randomUUID().toString().replace("-", "") }"
        val keyJs = JSONObject.quote(key)
        val script = """
            window[$keyJs] = '';
            window.__TAURI_INTERNALS__.invoke(${JSONObject.quote(command)}, $args)
              .then(value => window[$keyJs] = 'OK:' + JSON.stringify(value),
                    error => window[$keyJs] = 'ERR:' + (typeof error === 'object' ? JSON.stringify(error) : String(error)));
        """.trimIndent()
        evaluate(view, script)
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        var result = ""
        while (SystemClock.elapsedRealtime() < deadline) {
            result = evaluate(view, "window[$keyJs] || ''")
            if (result.startsWith("OK:") || result.startsWith("ERR:")) break
            Thread.sleep(100)
        }
        if (result.startsWith("ERR:")) throw AssertionError("Tauri command $command failed: ${result.removePrefix("ERR:")}")
        assertTrue("Tauri command $command timed out", result.startsWith("OK:"))
        return result.removePrefix("OK:")
    }

    private fun evaluate(view: WebView, script: String): String {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
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

    companion object {
        private const val TAG = "Zownload5A09"
    }
}
