// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Channel
import app.tauri.plugin.Plugin
import java.io.File
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

@InvokeArg
class SmokeArgs {
    lateinit var value: String
}

@InvokeArg
class DownloadMp3Args {
    lateinit var url: String
    lateinit var itemId: String
    var onProgress: Channel? = null
}

@InvokeArg
class CancelWorkArgs {
    lateinit var id: String
}

@InvokeArg
class OpenZipArgs {
    lateinit var name: String
}

@InvokeArg
class ZipChunkArgs {
    lateinit var id: String
    lateinit var data: String
}

@InvokeArg
class ZipIdArgs {
    lateinit var id: String
}

private class PendingZip(
    val id: String,
    val uri: Uri,
    val name: String,
    val stream: OutputStream,
    var bytes: Long = 0,
)

@TauriPlugin
class AndroidSpikePlugin(private val activity: Activity) : Plugin(activity) {
    // One transient output handle, not a Kotlin work queue. Rust owns the ZIP.
    private var pendingZip: PendingZip? = null

    private fun discardZip(row: PendingZip): Int {
        try { row.stream.close() } catch (error: Exception) { Log.w("Zownload0C13", "ZIP_CLOSE_FAILED", error) }
        val deleted = activity.contentResolver.delete(row.uri, null, null)
        Log.i("Zownload0C13", "ZIP_DELETED uri=${row.uri} deleted=$deleted")
        return deleted
    }

    @Command
    @Synchronized
    fun openZip(invoke: Invoke) {
        try {
            if (Build.VERSION.SDK_INT < 29) throw IOException("Pending Downloads rows require API 29")
            if (pendingZip != null) throw IOException("A ZIP output handle is already open")
            val name = invoke.parseArgs(OpenZipArgs::class.java).name
            if (!Regex("Zownload-0C13-[a-f0-9-]{36}\\.zip").matches(name)) throw IOException("Invalid ZIP name")
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("MediaStore refused the ZIP row")
            try {
                val stream = resolver.openOutputStream(uri, "w") ?: throw IOException("Cannot open ZIP row")
                val row = PendingZip(UUID.randomUUID().toString(), uri, name, stream)
                pendingZip = row
                val reply = JSObject()
                reply.put("id", row.id)
                reply.put("uri", uri.toString())
                Log.i("Zownload0C13", "ZIP_PENDING uri=$uri name=$name")
                invoke.resolve(reply)
            } catch (error: Exception) {
                val deleted = resolver.delete(uri, null, null)
                Log.e("Zownload0C13", "ZIP_OPEN_FAILED deleted=$deleted uri=$uri", error)
                throw error
            }
        } catch (error: Exception) {
            invoke.reject(error.message ?: error.javaClass.simpleName)
        }
    }

    @Command
    @Synchronized
    fun writeZipChunk(invoke: Invoke) {
        try {
            val args = invoke.parseArgs(ZipChunkArgs::class.java)
            val row = pendingZip ?: throw IOException("No pending ZIP row")
            if (row.id != args.id) throw IOException("ZIP handle does not match")
            val bytes = Base64.decode(args.data, Base64.DEFAULT)
            if (bytes.isEmpty() || bytes.size > 16 * 1024) throw IOException("Invalid ZIP chunk size")
            row.stream.write(bytes)
            row.bytes += bytes.size
            invoke.resolve(JSObject())
        } catch (error: Exception) {
            pendingZip?.let { row ->
                pendingZip = null
                try { discardZip(row) } catch (cleanup: Exception) { error.addSuppressed(cleanup) }
            }
            invoke.reject(error.message ?: error.javaClass.simpleName)
        }
    }

    @Command
    @Synchronized
    fun publishZip(invoke: Invoke) {
        try {
            val id = invoke.parseArgs(ZipIdArgs::class.java).id
            val row = pendingZip ?: throw IOException("No pending ZIP row")
            if (row.id != id) throw IOException("ZIP handle does not match")
            row.stream.close()
            val visible = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            if (activity.contentResolver.update(row.uri, visible, null, null) != 1) throw IOException("ZIP publish failed")
            pendingZip = null
            val reply = JSObject()
            reply.put("uri", row.uri.toString())
            reply.put("name", row.name)
            reply.put("bytes", row.bytes)
            Log.i("Zownload0C13", "ZIP_PUBLISHED uri=${row.uri} name=${row.name} bytes=${row.bytes}")
            invoke.resolve(reply)
        } catch (error: Exception) {
            pendingZip?.let { row ->
                pendingZip = null
                try { discardZip(row) } catch (cleanup: Exception) { error.addSuppressed(cleanup) }
            }
            invoke.reject(error.message ?: error.javaClass.simpleName)
        }
    }

    @Command
    @Synchronized
    fun abortZip(invoke: Invoke) {
        try {
            val id = invoke.parseArgs(ZipIdArgs::class.java).id
            val row = pendingZip ?: throw IOException("No pending ZIP row")
            if (row.id != id) throw IOException("ZIP handle does not match")
            pendingZip = null
            if (discardZip(row) != 1) throw IOException("Pending ZIP row was not deleted")
            invoke.resolve(JSObject())
        } catch (error: Exception) {
            invoke.reject(error.message ?: error.javaClass.simpleName)
        }
    }
    companion object {
        private val timeoutCallback = AtomicReference<(() -> Unit)?>(null)
        private val taskRemovedCallback = AtomicReference<(() -> Unit)?>(null)
        private val activeWorker = AtomicReference<Pair<String, java.util.concurrent.CountDownLatch>?>(null)
        // Instrumentation can slow a real transfer so Home remains observable.
        @Volatile internal var testRateLimit: String? = null

        fun onForegroundTimeout() {
            timeoutCallback.getAndSet(null)?.invoke()
        }

        fun onTaskRemoved(): Boolean {
            val callback = taskRemovedCallback.getAndSet(null) ?: return false
            callback()
            return true
        }
    }

    @Command
    fun startWorkService(invoke: Invoke) {
        val ack = SpikeDownloadService.start(activity.applicationContext)
        Thread {
            val error = ack.await()
            if (error == null) invoke.resolve(JSObject())
            else {
                SpikeDownloadService.stop(activity.applicationContext)
                invoke.reject(error)
            }
        }.start()
    }

    @Command
    fun stopWorkService(invoke: Invoke) {
        SpikeDownloadService.stop(activity.applicationContext)
        invoke.resolve(JSObject())
    }

    @Command
    fun cancelWork(invoke: Invoke) {
        val id = invoke.parseArgs(CancelWorkArgs::class.java).id
        val worker = activeWorker.get()
        if (worker == null || worker.first != id) {
            invoke.reject("Active engine ID does not match cancellation request")
            return
        }
        Thread {
            try {
                val killed = AndroidEngineAdapter(activity.applicationContext).cancel(id)
                val exited = worker.second.await(20, java.util.concurrent.TimeUnit.SECONDS)
                Log.i("Zownload0C10", "ENGINE_CANCEL id=$id killed=$killed workerExited=$exited")
                if (exited) invoke.resolve(JSObject())
                else invoke.reject("Engine worker did not exit after cancellation")
            } catch (error: Exception) {
                invoke.reject(error.message ?: error.javaClass.simpleName)
            }
        }.start()
    }

    @Command
    fun smoke(invoke: Invoke) {
        val args = invoke.parseArgs(SmokeArgs::class.java)
        val reply = JSObject()
        reply.put("value", args.value)
        invoke.resolve(reply)
    }

    @Command
    fun downloadMp3(invoke: Invoke) {
        val args = invoke.parseArgs(DownloadMp3Args::class.java)
        val url = args.url
        val itemId = args.itemId
        val parsed = Uri.parse(url)
        val host = parsed.host?.lowercase()
        if (parsed.scheme != "https" || host !in setOf("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be")) {
            invoke.reject("0C-06 requires a public HTTPS YouTube URL")
            return
        }
        if (!Regex("[a-f0-9-]{36}").matches(itemId)) {
            invoke.reject("Invalid Rust queue item ID")
            return
        }
        val id = UUID.randomUUID().toString()
        val finished = AtomicBoolean(false)
        val timedOut = AtomicBoolean(false)
        val workerExited = java.util.concurrent.CountDownLatch(1)
        val workerHandle = id to workerExited
        // Reserve the engine before starting a worker, closing the gap in
        // which an update could otherwise swap archives before execute().
        try {
            VerifiedYtDlpUpdate.beginJob()
        } catch (error: Exception) {
            invoke.reject(error.message ?: error.javaClass.simpleName)
            return
        }
        activeWorker.set(workerHandle)
        // Only a transient cancellation handle crosses into the service. The
        // queue state and timeout decision remain in Rust.
        val onTimeout: () -> Unit = {
            if (finished.compareAndSet(false, true)) {
                // Keep yt-dlp's .part for the Rust-owned paused item's Continue.
                timedOut.set(true)
                val reply = JSObject()
                reply.put("timedOut", true)
                invoke.resolve(reply)
                Thread {
                    try {
                        AndroidEngineAdapter(activity.applicationContext).cancel(id)
                    } catch (error: Exception) {
                        Log.e("Zownload0C08", "TIMEOUT_CANCEL_FAILED", error)
                    }
                }.start()
                Log.i("Zownload0C08", "TIMEOUT_CALLBACK_RETURNED_TO_RUST")
            }
        }
        timeoutCallback.set(onTimeout)
        val onTaskRemoved: () -> Unit = {
            if (finished.compareAndSet(false, true)) {
                val reply = JSObject()
                reply.put("taskRemoved", true)
                reply.put("id", id)
                invoke.resolve(reply)
                Log.i("Zownload0C10", "TASK_REMOVED_RETURNED_TO_RUST id=$id")
            }
        }
        taskRemovedCallback.set(onTaskRemoved)
        // Tauri dispatches mobile commands on the main thread. Engine work and
        // the MediaStore copy must run on a worker so the WebView stays live.
        Thread {
            // The Rust item ID fixes the output path across process death.
            // Android cannot run this finally block after SIGKILL, so yt-dlp's
            // .part remains here until the user explicitly continues.
            val directory = File(activity.cacheDir, "zownload-0c-06/$itemId")
            try {
                if (finished.get()) return@Thread
                if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException("Cannot create private output directory")
                val part = directory.listFiles()?.firstOrNull { it.name.endsWith(".part") }
                if (part != null) Log.i("Zownload0C11", "RESUME_INPUT item=$itemId name=${part.name} bytes=${part.length()}")
                val engine = AndroidEngineAdapter(activity.applicationContext)
                var lastPercent = -1
                val result = engine.downloadOne(
                    url,
                    File(directory, "audio.%(ext)s"),
                    id,
                    testRateLimit,
                    { percent, _, _ ->
                        if (percent.isFinite() && percent >= 0f && percent <= 100f) {
                            val whole = percent.toInt()
                            if (whole > lastPercent) {
                                lastPercent = whole
                                val update = JSObject()
                                update.put("percent", whole.toDouble())
                                args.onProgress?.send(update)
                                Log.i("Zownload0C09", "ENGINE_PROGRESS percent=$whole")
                            }
                        }
                    },
                    { error -> Log.e("Zownload0C06", "Engine failure", error) },
                )
                (result.stderr + "\n" + result.stdout).lineSequence().filter { line ->
                    line.contains("yt-dlp version") || line.contains("JS runtimes:") ||
                        line.contains("Optional libraries:") || line.contains("[ExtractAudio]") ||
                        line.contains("ffmpeg command line") || line.contains("Deleting original file") ||
                        line.contains("Resuming download at byte") || line.contains("[download] Destination:")
                }.forEach { Log.i("Zownload0C06", "ENGINE $it") }
                if (finished.get()) return@Thread
                val mp3 = File(directory, "audio.mp3")
                val published = publishMp3(activity.applicationContext, mp3, "Zownload-0C06-$id.mp3")
                Log.i("Zownload0C06", "PUBLISHED uri=${published.uri} name=${published.displayName} mime=${published.mimeType} sha256=${published.sha256} bytes=${published.bytes}")
                val reply = JSObject()
                reply.put("id", id)
                reply.put("uri", published.uri)
                if (finished.compareAndSet(false, true)) {
                    invoke.resolve(reply)
                } else {
                    // A timeout can arrive while MediaStore is publishing.
                    activity.contentResolver.delete(Uri.parse(published.uri), null, null)
                }
            } catch (error: Exception) {
                Log.e("Zownload0C06", "FAILED", error)
                if (finished.compareAndSet(false, true)) invoke.reject(error.message ?: error.javaClass.simpleName)
            } finally {
                timeoutCallback.compareAndSet(onTimeout, null)
                taskRemovedCallback.compareAndSet(onTaskRemoved, null)
                if (timedOut.get()) {
                    Log.i("Zownload0C15", "TIMEOUT_PART_PRESERVED item=$itemId")
                } else {
                    directory.deleteRecursively()
                }
                workerExited.countDown()
                activeWorker.compareAndSet(workerHandle, null)
                VerifiedYtDlpUpdate.endJob()
            }
        }.start()
    }
}
