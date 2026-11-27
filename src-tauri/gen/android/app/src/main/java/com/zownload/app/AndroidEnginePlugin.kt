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
import java.util.concurrent.atomic.AtomicReference

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

@InvokeArg
class AndroidCreatePendingZipArgs {
    lateinit var displayName: String
}

@InvokeArg
class AndroidOpenPendingZipArgs {
    lateinit var uri: String
}

@InvokeArg
class AndroidPublishPendingZipArgs {
    lateinit var uri: String
    var expectedBytes: Long = 0
}

@InvokeArg
class AndroidCleanupQueueArgs {
    lateinit var queueId: String
}

@InvokeArg
class AndroidLifecycleChannelArgs {
    var onSignal: Channel? = null
}

@InvokeArg
class AndroidForegroundServiceArgs {
    lateinit var title: String
    lateinit var detail: String
    var percent: Int = 0
    var indeterminate: Boolean = true
    lateinit var timeoutDetail: String
}

@InvokeArg
class AndroidForegroundProgressArgs {
    lateinit var title: String
    lateinit var detail: String
    var percent: Int = 0
    var indeterminate: Boolean = true
}

@TauriPlugin
class AndroidEnginePlugin(private val activity: Activity) : Plugin(activity) {
    private val adapter by lazy {
        AndroidEngineAdapter(activity.applicationContext).also { activeAdapter.set(it) }
    }

    companion object {
        private val lifecycleChannel = AtomicReference<Channel?>(null)
        private val activeAdapter = AtomicReference<AndroidEngineAdapter?>(null)

        internal fun onTaskRemoved(): Boolean = dispatchLifecycleSignal("task_removed")

        internal fun onForegroundTimeout(): Boolean = dispatchLifecycleSignal("foreground_timeout")

        internal fun hasActiveOperations(): Boolean = activeAdapter.get()?.hasActiveOperations() == true

        private fun dispatchLifecycleSignal(kind: String): Boolean {
            activeAdapter.get()?.cancelAllActive()
            val channel = lifecycleChannel.get() ?: return false
            // Never block the Android main thread inside onTaskRemoved/onTimeout:
            // Rust calls back into Tauri mobile plugin commands on the main Looper.
            Thread({
                try {
                    val payload = JSObject()
                    payload.put("kind", kind)
                    channel.send(payload)
                } catch (_: Exception) {
                }
            }, "zownload-lifecycle-$kind").start()
            return true
        }
    }

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
    fun createPendingZip(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidCreatePendingZipArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val pending = createPendingMediaStoreZip(activity.applicationContext, args.displayName)
            JSONObject()
                .put("uri", pending.uri)
                .put("displayName", pending.displayName)
        }
    }

    @Command
    fun openPendingZipFd(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidOpenPendingZipArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val fd = openPendingMediaStoreZipFd(activity.applicationContext, args.uri)
            JSONObject().put("fd", fd)
        }
    }

    @Command
    fun publishPendingZip(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidPublishPendingZipArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val published = publishPendingMediaStoreZip(
                activity.applicationContext,
                args.uri,
                args.expectedBytes,
            )
            JSONObject()
                .put("uri", published.uri)
                .put("displayName", published.displayName)
                .put("bytes", published.bytes)
        }
    }

    @Command
    fun deletePendingZip(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidOpenPendingZipArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val deleted = deletePendingMediaStoreZip(activity.applicationContext, args.uri)
            JSONObject().put("deleted", deleted)
        }
    }

    @Command
    fun cleanupOperation(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidCancelArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val cleaned = deleteOperationWorkDir(activity.cacheDir, args.operationId)
            JSONObject().put("cleaned", cleaned)
        }
    }

    @Command
    fun cleanupQueueCache(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidCleanupQueueArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        runOnWorker(invoke) {
            val cleaned = deleteQueueCacheDirs(activity.cacheDir, args.queueId)
            JSONObject().put("cleaned", cleaned)
        }
    }

    @Command
    fun registerLifecycleChannel(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidLifecycleChannelArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        lifecycleChannel.set(args.onSignal)
        invoke.resolve(success(JSONObject().put("registered", args.onSignal != null)))
    }

    @Command
    fun startForegroundService(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidForegroundServiceArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        val ack = DownloadForegroundService.start(
            activity.applicationContext,
            args.title,
            args.detail,
            args.percent,
            args.indeterminate,
            args.timeoutDetail,
        )
        runOnWorker(invoke) {
            val error = ack.await()
            if (error != null) {
                DownloadForegroundService.stop(activity.applicationContext)
                throw EngineBridgeException("permission_denied", error)
            }
            JSONObject().put("started", true)
        }
    }

    @Command
    fun updateForegroundProgress(invoke: Invoke) {
        val args = try {
            invoke.parseArgs(AndroidForegroundProgressArgs::class.java)
        } catch (error: Exception) {
            invoke.resolve(failure(error))
            return
        }
        DownloadForegroundService.updateProgress(
            activity.applicationContext,
            args.title,
            args.detail,
            args.percent,
            args.indeterminate,
        )
        invoke.resolve(success(JSONObject().put("updated", true)))
    }

    @Command
    fun stopForegroundService(invoke: Invoke) {
        DownloadForegroundService.stop(activity.applicationContext)
        invoke.resolve(success(JSONObject().put("stopped", true)))
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
