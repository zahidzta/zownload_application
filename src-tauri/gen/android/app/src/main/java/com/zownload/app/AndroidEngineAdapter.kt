// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.mapper.VideoInfo
import java.io.File

// Rust owns job state. This adapter supplies engine progress to the plugin,
// which forwards it to Rust without keeping a second queue.
internal class AndroidEngineAdapter(
    context: Context,
    private val packageProvider: AndroidEnginePackage = BundledEnginePackage(),
) {
    init {
        packageProvider.initialize(context.applicationContext)
    }

    fun analyze(url: String): VideoInfo {
        VerifiedYtDlpUpdate.beginJob()
        try {
            val request = YoutubeDLRequest(url)
            packageProvider.configure(request)
            return YoutubeDL.getInstance().getInfo(request)
        } finally {
            VerifiedYtDlpUpdate.endJob()
        }
    }

    fun downloadOne(
        url: String,
        output: File,
        processId: String,
        rateLimit: String?,
        onProgress: (Float, Long, String) -> Unit,
        onError: (Throwable) -> Unit,
    ): EngineRun {
        VerifiedYtDlpUpdate.beginJob()
        try {
            val request = YoutubeDLRequest(url)
            packageProvider.configure(request)
            request.addOption("--no-playlist")
            request.addOption("--extract-audio")
            request.addOption("--audio-format", "mp3")
            request.addOption("--audio-quality", "128K")
            request.addOption("-f", "bestaudio/best")
            request.addOption("--verbose")
            request.addOption("--no-mtime")
            request.addOption("--continue")
            request.addOption("--part")
            if (BuildConfig.DEBUG && rateLimit != null) request.addOption("--limit-rate", rateLimit)
            request.addOption("-o", output.absolutePath)
            return try {
                val result = YoutubeDL.getInstance().execute(request, processId, onProgress)
                EngineRun(result.out, result.err)
            } catch (error: Exception) {
                onError(error)
                throw error
            }
        } finally {
            VerifiedYtDlpUpdate.endJob()
        }
    }

    fun cancel(processId: String): Boolean = YoutubeDL.getInstance().destroyProcessById(processId)
}

internal data class EngineRun(val stdout: String, val stderr: String)

// The provider lets the library choose its own executable paths. Later
// traceable binaries can be supplied by another provider without changing the
// analyze/download/cancel adapter or assuming any bundled FFmpeg build flags.
internal interface AndroidEnginePackage {
    val version: String
    val ytDlpVersion: String
    val ejsVersion: String
    val paths: EnginePaths
    fun initialize(context: Context)
    fun configure(request: YoutubeDLRequest)
}

internal data class EnginePaths(
    val nativeLibraryDirectory: String,
    val ffmpegExecutable: String? = null,
    val quickJsExecutable: String? = null,
    val ytDlpArchive: String? = null,
)

internal class BundledEnginePackage : AndroidEnginePackage {
    override val version = "0.18.1"
    override val ytDlpVersion: String
        get() = if (VerifiedYtDlpUpdate.sha256(File(paths.ytDlpArchive!!)) == VerifiedYtDlpUpdate.candidateHash) {
            VerifiedYtDlpUpdate.candidateVersion
        } else {
            VerifiedYtDlpUpdate.baselineVersion
        }
    override val ejsVersion = "0.8.0"
    override lateinit var paths: EnginePaths
        private set

    @Synchronized
    override fun initialize(context: Context) {
        VerifiedYtDlpUpdate.initialize(context)
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        val root = File(context.noBackupFilesDir, YoutubeDL.baseName)
        paths = EnginePaths(
            nativeLibraryDirectory = context.applicationInfo.nativeLibraryDir,
            quickJsExecutable = File(context.applicationInfo.nativeLibraryDir, "libqjs.so").absolutePath,
            ytDlpArchive = File(root, "${YoutubeDL.ytdlpDirName}/${YoutubeDL.ytdlpBin}").absolutePath,
        )
    }

    override fun configure(request: YoutubeDLRequest) {
        // The 0.18.1 library supplies its own --js-runtimes and FFmpeg paths.
        // The app's pinned native source replaces that fixed QuickJS path.
        // The FFmpeg build configuration is deliberately not assumed here.
    }
}
