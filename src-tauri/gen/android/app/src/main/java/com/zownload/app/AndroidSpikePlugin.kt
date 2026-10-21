// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.net.Uri
import android.util.Log
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.File
import java.util.UUID

@InvokeArg
class SmokeArgs {
    lateinit var value: String
}

@InvokeArg
class DownloadMp3Args {
    lateinit var url: String
}

@TauriPlugin
class AndroidSpikePlugin(private val activity: Activity) : Plugin(activity) {
    @Command
    fun smoke(invoke: Invoke) {
        val args = invoke.parseArgs(SmokeArgs::class.java)
        val reply = JSObject()
        reply.put("value", args.value)
        invoke.resolve(reply)
    }

    @Command
    fun downloadMp3(invoke: Invoke) {
        val url = invoke.parseArgs(DownloadMp3Args::class.java).url
        val parsed = Uri.parse(url)
        val host = parsed.host?.lowercase()
        if (parsed.scheme != "https" || host !in setOf("youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be")) {
            invoke.reject("0C-06 requires a public HTTPS YouTube URL")
            return
        }
        // Tauri dispatches mobile commands on the main thread. Engine work and
        // the MediaStore copy must run on a worker so the WebView stays live.
        Thread {
            val id = UUID.randomUUID().toString()
            val directory = File(activity.cacheDir, "zownload-0c-06/$id")
            try {
                if (!directory.mkdirs()) throw IllegalStateException("Cannot create private output directory")
                val engine = AndroidEngineAdapter(activity.applicationContext)
                val result = engine.downloadOne(
                    url,
                    File(directory, "audio.%(ext)s"),
                    id,
                    { percent, _, _ -> if (percent >= 100f) Log.i("Zownload0C06", "download reached 100%") },
                    { error -> Log.e("Zownload0C06", "Engine failure", error) },
                )
                (result.stderr + "\n" + result.stdout).lineSequence().filter { line ->
                    line.contains("yt-dlp version") || line.contains("JS runtimes:") ||
                        line.contains("Optional libraries:") || line.contains("[ExtractAudio]") ||
                        line.contains("ffmpeg command line") || line.contains("Deleting original file")
                }.forEach { Log.i("Zownload0C06", "ENGINE $it") }
                val mp3 = File(directory, "audio.mp3")
                val published = publishMp3(activity.applicationContext, mp3, "Zownload-0C06-$id.mp3")
                Log.i("Zownload0C06", "PUBLISHED uri=${published.uri} name=${published.displayName} mime=${published.mimeType} sha256=${published.sha256} bytes=${published.bytes}")
                val reply = JSObject()
                reply.put("id", id)
                reply.put("uri", published.uri)
                invoke.resolve(reply)
            } catch (error: Exception) {
                Log.e("Zownload0C06", "FAILED", error)
                invoke.reject(error.message ?: error.javaClass.simpleName)
            } finally {
                directory.deleteRecursively()
            }
        }.start()
    }
}
