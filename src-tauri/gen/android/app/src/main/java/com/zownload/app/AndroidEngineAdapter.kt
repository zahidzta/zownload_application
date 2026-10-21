// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoInfo
import java.io.File

// This is a compile-only adapter for 0C-04B. Rust will own job state and call
// it through the plugin in later tasks; none of these methods run on a device yet.
internal class AndroidEngineAdapter(
    context: Context,
    private val packageProvider: AndroidEnginePackage = BundledEnginePackage(),
) {
    init {
        packageProvider.initialize(context.applicationContext)
    }

    fun analyze(url: String): VideoInfo {
        val request = YoutubeDLRequest(url)
        packageProvider.configure(request)
        return YoutubeDL.getInstance().getInfo(request)
    }

    fun downloadOne(
        url: String,
        output: File,
        processId: String,
        onProgress: (Float, Long, String) -> Unit,
        onError: (Throwable) -> Unit,
    ): String {
        val request = YoutubeDLRequest(url)
        packageProvider.configure(request)
        request.addOption("--no-playlist")
        request.addOption("--extract-audio")
        request.addOption("--audio-format", "mp3")
        request.addOption("--audio-quality", "128K")
        request.addOption("-o", output.absolutePath)
        return try {
            YoutubeDL.getInstance().execute(request, processId, onProgress).out
        } catch (error: Exception) {
            onError(error)
            throw error
        }
    }

    fun cancel(processId: String): Boolean = YoutubeDL.getInstance().destroyProcessById(processId)
}

// The bundled provider lets the library choose its own executables. Later
// traceable binaries can be supplied by another provider without changing the
// analyze/download/cancel adapter or assuming any bundled FFmpeg build flags.
internal interface AndroidEnginePackage {
    val version: String
    val paths: EnginePaths
    fun initialize(context: Context)
    fun configure(request: YoutubeDLRequest)
}

internal data class EnginePaths(
    val nativeLibraryDirectory: String,
    val ffmpegExecutable: String? = null,
    val quickJsExecutable: String? = null,
)

internal class BundledEnginePackage : AndroidEnginePackage {
    override val version = "0.18.1"
    override lateinit var paths: EnginePaths
        private set

    override fun initialize(context: Context) {
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        paths = EnginePaths(context.applicationInfo.nativeLibraryDir)
    }

    override fun configure(request: YoutubeDLRequest) {
        // The pinned library supplies its own paths, including FFmpeg and QuickJS.
        // Their configuration is deliberately not assumed by the adapter.
    }
}
