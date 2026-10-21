// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import android.system.Os
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.R as EngineR
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

// The library's tagged updater has no hash check or rollback. All swaps go
// through this single process-wide gate; Rust still owns the download queue.
internal object VerifiedYtDlpUpdate {
    const val baselineVersion = "2026.08.19"
    const val baselineHash = "1fa6733c37ea6fb51c99ad8fe785e7b7e5f3246c9b980230329d4fb72ed8d4d6"
    const val candidateVersion = "2026.10.21"
    const val candidateEjsVersion = "0.8.0"
    const val candidateHash = "b7af77f686e95f7845ce8d09d21957718febb8b48b30555adb9dd2292ad7bf14"
    private const val candidateUrl = "https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.21/yt-dlp"
    private const val maxBytes = 20L * 1024 * 1024
    private val gate = Any()
    private var activeJobs = 0
    private var updating = false

    fun beginJob() = synchronized(gate) {
        if (updating) throw IOException("yt-dlp update is active")
        activeJobs++
    }

    fun endJob() = synchronized(gate) {
        check(activeJobs > 0)
        activeJobs--
    }

    fun activeArchive(context: Context): File = File(
        context.noBackupFilesDir,
        "${YoutubeDL.baseName}/${YoutubeDL.ytdlpDirName}/${YoutubeDL.ytdlpBin}",
    )

    // A crash between archive and marker renames restores the bundled baseline
    // at next startup. The app never trusts an unmarked candidate on disk.
    fun initialize(context: Context) = synchronized(gate) {
        if (updating) throw IOException("yt-dlp update is active")
        val target = activeArchive(context)
        val marker = File(target.parentFile, "active-version")
        val currentHash = if (target.isFile) sha256(target) else null
        if (currentHash == candidateHash && marker.isFile &&
            marker.readText() == "$candidateVersion:$candidateHash"
        ) return@synchronized
        if (currentHash == baselineHash) {
            marker.delete()
            return@synchronized
        }
        restoreBaseline(context)
    }

    fun updateFromRelease(context: Context) = exclusiveUpdate {
        initializeForUpdate(context)
        val connection = URL(candidateUrl).openConnection()
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.getInputStream().use { installCandidate(context, it) }
    }

    // Used by the device probe to prove a failed checksum preserves the active
    // file. Production and probe use the same verification/swap code.
    internal fun updateFromStream(context: Context, input: InputStream) = exclusiveUpdate {
        initializeForUpdate(context)
        installCandidate(context, input)
    }

    fun rollbackAfterFailure(context: Context, reason: String) = exclusiveUpdate {
        initializeForUpdate(context)
        if (sha256(activeArchive(context)) != candidateHash) {
            throw IOException("No accepted candidate to roll back")
        }
        Log.i("Zownload0C14", "POST_ACCEPT_FAILURE reason=$reason")
        restoreBaseline(context)
        val observed = runVersion(context, activeArchive(context))
        if (observed != baselineVersion) throw IOException("Baseline recovery health check failed: $observed")
        Log.i("Zownload0C14", "ROLLBACK_OK version=$observed hash=${sha256(activeArchive(context))}")
    }

    private inline fun <T> exclusiveUpdate(block: () -> T): T {
        synchronized(gate) {
            if (updating || activeJobs != 0) throw IOException("yt-dlp is busy; update refused")
            updating = true
        }
        try {
            return block()
        } finally {
            synchronized(gate) { updating = false }
        }
    }

    private fun initializeForUpdate(context: Context) {
        // The caller holds the update gate; unlike normal startup, this does
        // not reject its own update flag.
        val target = activeArchive(context)
        val marker = File(target.parentFile, "active-version")
        val hash = if (target.isFile) sha256(target) else null
        if (hash == baselineHash) return
        if (hash == candidateHash && marker.isFile && marker.readText() == "$candidateVersion:$candidateHash") return
        restoreBaseline(context)
    }

    private fun installCandidate(context: Context, input: InputStream) {
        val target = activeArchive(context)
        val staged = File(target.parentFile, "yt-dlp.candidate")
        var accepted = false
        try {
            copyBounded(input, staged)
            val hash = sha256(staged)
            if (hash != candidateHash) throw IOException("Candidate SHA-256 mismatch: $hash")
            verifyZipIdentity(staged)
            val preflight = runVersion(context, staged)
            if (preflight != candidateVersion) throw IOException("Candidate preflight failed: $preflight")
            Log.i("Zownload0C14", "CANDIDATE_VERIFIED version=$preflight ejs=$candidateEjsVersion hash=$hash")

            // Same-directory POSIX rename replaces the complete archive at
            // once. No worker can start while the update flag is set.
            Os.rename(staged.absolutePath, target.absolutePath)
            accepted = true
            writeMarker(target, "$candidateVersion:$candidateHash")
            val observed = runVersion(context, target)
            if (observed != candidateVersion) throw IOException("Accepted candidate health check failed: $observed")
            Log.i("Zownload0C14", "UPDATE_OK version=$observed ejs=$candidateEjsVersion hash=${sha256(target)}")
        } catch (error: Exception) {
            if (accepted) {
                try { restoreBaseline(context) }
                catch (rollback: Exception) { error.addSuppressed(rollback) }
            }
            throw error
        } finally {
            staged.delete()
        }
    }

    private fun verifyZipIdentity(file: File) {
        ZipFile(file).use { zip ->
            val version = zip.getEntry("yt_dlp/version.py") ?: throw IOException("yt-dlp version missing")
            val ejs = zip.getEntry("yt_dlp_ejs/_version.py") ?: throw IOException("EJS version missing")
            val versionText = zip.getInputStream(version).bufferedReader().use { it.readText() }
            val ejsText = zip.getInputStream(ejs).bufferedReader().use { it.readText() }
            if (!versionText.contains("__version__ = '$candidateVersion'") ||
                !ejsText.contains("__version__ = version = '$candidateEjsVersion'")
            ) throw IOException("Candidate yt-dlp/EJS identity mismatch")
        }
    }

    private fun restoreBaseline(context: Context) {
        val target = activeArchive(context)
        if (!target.parentFile.isDirectory && !target.parentFile.mkdirs()) throw IOException("Cannot create yt-dlp directory")
        val staged = File(target.parentFile, "yt-dlp.baseline")
        try {
            context.resources.openRawResource(EngineR.raw.ytdlp).use { copyBounded(it, staged) }
            if (sha256(staged) != baselineHash) throw IOException("Bundled baseline SHA-256 mismatch")
            Os.rename(staged.absolutePath, target.absolutePath)
            File(target.parentFile, "active-version").delete()
        } finally {
            staged.delete()
        }
    }

    private fun writeMarker(target: File, text: String) {
        val staged = File(target.parentFile, "active-version.staging")
        try {
            FileOutputStream(staged).use { out ->
                out.write(text.toByteArray(Charsets.UTF_8))
                out.fd.sync()
            }
            Os.rename(staged.absolutePath, File(target.parentFile, "active-version").absolutePath)
        } finally {
            staged.delete()
        }
    }

    private fun copyBounded(input: InputStream, target: File) {
        FileOutputStream(target).use { out ->
            val bytes = ByteArray(8192)
            var total = 0L
            while (true) {
                val count = input.read(bytes)
                if (count < 0) break
                total += count
                if (total > maxBytes) throw IOException("yt-dlp candidate exceeds size limit")
                out.write(bytes, 0, count)
            }
            out.fd.sync()
        }
    }

    // Mirror the tagged library's Python environment for a staged-file check.
    // --version does not access YouTube or mutate the queue.
    fun runVersion(context: Context, archive: File): String {
        val root = File(context.noBackupFilesDir, YoutubeDL.baseName)
        val packages = File(root, "packages")
        val native = File(context.applicationInfo.nativeLibraryDir)
        val pythonHome = File(packages, "python/usr")
        val process = ProcessBuilder(File(native, "libpython.so").absolutePath, archive.absolutePath, "--version")
            .redirectErrorStream(true)
            .apply {
                environment()["LD_LIBRARY_PATH"] = listOf("python", "ffmpeg", "aria2c")
                    .joinToString(":") { File(packages, "$it/usr/lib").absolutePath }
                environment()["SSL_CERT_FILE"] = File(pythonHome, "etc/tls/cert.pem").absolutePath
                environment()["PYTHONHOME"] = pythonHome.absolutePath
                environment()["HOME"] = pythonHome.absolutePath
                environment()["TMPDIR"] = context.cacheDir.absolutePath
                environment()["PATH"] = System.getenv("PATH") + ":" + native.absolutePath
            }.start()
        if (!process.waitFor(30, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            throw IOException("yt-dlp version check timed out")
        }
        val output = process.inputStream.bufferedReader().use { it.readText().trim() }
        if (process.exitValue() != 0) throw IOException("yt-dlp version check failed: $output")
        return output
    }

    fun sha256(file: File): String {
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
