// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Channel
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import org.json.JSONObject
import java.io.File

@InvokeArg
class AndroidAnalyzeArgs {
    lateinit var url: String
}

@InvokeArg
class AndroidQualityArgs {
    lateinit var type: String
    var height: Int? = null
    var bitrate: Int? = null
}

@InvokeArg
class AndroidDownloadRequestArgs {
    lateinit var url: String
    lateinit var format: String
    lateinit var quality: AndroidQualityArgs
    var isPlaylist: Boolean = false
}

@InvokeArg
class AndroidDownloadOneArgs {
    lateinit var operationId: String
    lateinit var request: AndroidDownloadRequestArgs
    var onProgress: Channel? = null
}

@InvokeArg
class AndroidCancelArgs {
    lateinit var operationId: String
}

@InvokeArg
class AndroidPublishOutputArgs {
    lateinit var path: String
    lateinit var displayName: String
    lateinit var format: String
}

@TauriPlugin
class AndroidEnginePlugin(private val activity: Activity) : Plugin(activity) {
    private val adapter by lazy { AndroidEngineAdapter(activity.applicationContext) }

    // These methods bridge a single engine call. Queue state and retry policy
    // stay in Rust; worker threads keep blocking Python calls off the UI thread.
    @Command
    fun analyze(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidAnalyzeArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) { adapter.analyze(args.url) }
    }

    @Command
    fun downloadOne(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidDownloadOneArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        val outputDirectory = File(activity.cacheDir, "zownload-engine/${args.operationId}")
        val outputTemplate = File(outputDirectory, "%(title).200B [%(id)s].%(ext)s").absolutePath
        val request = requestJson(args.request)
        runOnWorker(invoke) {
            adapter.downloadOne(request, args.operationId, outputTemplate) { progress ->
                try {
                    val payload = JSObject()
                    val keys = progress.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        payload.put(key, progress.get(key))
                    }
                    args.onProgress?.send(payload)
                } catch (_: Exception) {
                    // A detached Rust caller should not interrupt the engine.
                }
            }
        }
    }

    @Command
    fun cancel(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidCancelArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) { JSONObject().put("cancelled", adapter.cancel(args.operationId)) }
    }

    @Command
    fun publishOutput(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidPublishOutputArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val cacheRoot = File(activity.cacheDir, "zownload-engine").canonicalFile
            val source = File(args.path).canonicalFile
            if (!source.path.startsWith(cacheRoot.path + File.separator)) {
                throw EngineBridgeException("engine_missing", "Android output is outside the private engine cache")
            }
            val published = publishMediaStoreOutput(
                activity.applicationContext,
                source,
                args.displayName,
                args.format,
            )
            JSONObject()
                .put("displayName", published.displayName)
                .put("mimeType", published.mimeType)
                .put("bytes", published.bytes)
        }
    }

    @Command
    fun checkUpdate(invoke: Invoke) = runOnWorker(invoke) { adapter.checkUpdate() }

    @Command
    fun update(invoke: Invoke) = runOnWorker(invoke) { adapter.update() }

    private fun requestJson(request: AndroidDownloadRequestArgs): JSONObject {
        val quality = JSONObject().put("type", request.quality.type)
        request.quality.height?.let { quality.put("height", it) }
        request.quality.bitrate?.let { quality.put("bitrate", it) }
        return JSONObject()
            .put("url", request.url)
            .put("format", request.format)
            .put("quality", quality)
            .put("isPlaylist", request.isPlaylist)
    }

    private fun runOnWorker(invoke: Invoke, operation: () -> JSONObject) {
        Thread({
            try {
                invoke.resolve(success(operation()))
            } catch (error: Exception) {
                invoke.resolve(failure(error))
            }
        }, "zownload-android-engine").start()
    }

    private fun success(value: JSONObject): JSObject {
        val result = JSObject()
        result.put("ok", true)
        result.put("value", value)
        return result
    }

    private fun failure(error: Throwable): JSObject {
        val typed = error as? EngineBridgeException
        val detail = JSObject()
        detail.put("code", typed?.code ?: "unknown")
        detail.put("detail", typed?.message ?: error.message ?: error.javaClass.simpleName)
        val result = JSObject()
        result.put("ok", false)
        result.put("error", detail)
        return result
    }
}
