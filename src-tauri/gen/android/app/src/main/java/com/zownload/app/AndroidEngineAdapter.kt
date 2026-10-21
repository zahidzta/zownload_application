// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.R as EngineR
import com.yausername.youtubedl_android.mapper.VideoInfo
import java.io.File
import java.io.IOException
import java.security.MessageDigest

// Rust will own job state and call this adapter through the plugin in later
// tasks. The 0C-05 device test exercises package setup and a smoke request.
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
    override val ytDlpVersion = "2026.08.19"
    override val ejsVersion = "0.8.0"
    override lateinit var paths: EnginePaths
        private set

    @Synchronized
    override fun initialize(context: Context) {
        installPinnedZipapp(context)
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

    private fun installPinnedZipapp(context: Context) {
        val root = File(context.noBackupFilesDir, YoutubeDL.baseName)
        val directory = File(root, YoutubeDL.ytdlpDirName)
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Cannot create yt-dlp directory")
        val target = File(directory, YoutubeDL.ytdlpBin)
        val expected = "1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6"
        if (target.isFile && sha256(target) == expected) return

        // Initialization precedes all spike jobs. A same-directory rename makes
        // an upgrade from the library's older copied zipapp visible at once.
        val staging = File(directory, "${YoutubeDL.ytdlpBin}.staging")
        try {
            context.resources.openRawResource(EngineR.raw.ytdlp).use { input ->
                staging.outputStream().use { output -> input.copyTo(output) }
            }
            if (sha256(staging) != expected) throw IOException("Pinned yt-dlp resource hash differs")
            if (!staging.renameTo(target)) throw IOException("Cannot activate pinned yt-dlp zipapp")
        } finally {
            staging.delete()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val bytes = ByteArray(8192)
            while (true) {
                val count = input.read(bytes)
                if (count < 0) break
                digest.update(bytes, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
