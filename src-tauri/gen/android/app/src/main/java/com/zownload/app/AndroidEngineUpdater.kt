// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import android.system.Os
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipFile

// This updater stages one official, hash-pinned yt-dlp release. The embedded
// interpreter activates it on next startup, leaving its current imports intact.
internal object AndroidEngineUpdater {
    const val candidateVersion = "2026.11.23"
    const val candidateEjsVersion = "0.8.0"
    private const val candidateHash = "e8665ed64d6b9172773e812f891fb707a0cb1ee8d9ef4fc1acb00cabee4c5256"
    private const val candidateUrl = "https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.23/yt-dlp"
    private const val maxBytes = 20L * 1024 * 1024

    fun activeArchive(context: Context): File? {
        val target = target(context)
        val marker = marker(context)
        if (!target.isFile) return null
        if (sha256(target) == candidateHash && marker.isFile &&
            marker.readText(Charsets.UTF_8) == "$candidateVersion:$candidateHash"
        ) return target

        target.delete()
        marker.delete()
        return null
    }

    fun activeVersion(context: Context): String? = activeArchive(context)?.let { candidateVersion }

    fun rollback(context: Context) {
        target(context).delete()
        marker(context).delete()
    }

    fun checkInfo(current: String): JSONObject {
        val available = current != candidateVersion
        return JSONObject()
            .put("current", current)
            .put("latest", candidateVersion)
            .put("updateAvailable", available)
            .put("outcome", if (available) "available" else "current")
    }

    fun update(context: Context, current: String): JSONObject {
        if (activeArchive(context) != null) {
            return JSONObject()
                .put("current", current)
                .put("latest", candidateVersion)
                .put("updateAvailable", false)
                .put("outcome", "pending")
                .put("pendingVersion", candidateVersion)
        }
        if (current == candidateVersion) return checkInfo(current)

        val directory = target(context).parentFile
            ?: throw IOException("Cannot locate the private Android engine directory")
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Cannot create the Android engine directory")
        val staged = File(directory, "yt-dlp.candidate.staging")
        try {
            val connection = URL(candidateUrl).openConnection()
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.getInputStream().use { copyBounded(it, staged) }
            if (sha256(staged) != candidateHash) throw IOException("yt-dlp candidate SHA-256 mismatch")
            verifyIdentity(staged)

            Os.rename(staged.absolutePath, target(context).absolutePath)
            writeMarker(context, "$candidateVersion:$candidateHash")
            return JSONObject()
                .put("current", current)
                .put("latest", candidateVersion)
                .put("updateAvailable", false)
                .put("outcome", "pending")
                .put("pendingVersion", candidateVersion)
        } catch (error: Exception) {
            staged.delete()
            throw error
        }
    }

    private fun target(context: Context) = File(context.noBackupFilesDir, "zownload-engine/yt-dlp.candidate")

    private fun marker(context: Context) = File(target(context).parentFile, "active-version")

    private fun writeMarker(context: Context, text: String) {
        val staged = File(target(context).parentFile, "active-version.staging")
        FileOutputStream(staged).use { output ->
            output.write(text.toByteArray(Charsets.UTF_8))
            output.fd.sync()
        }
        Os.rename(staged.absolutePath, marker(context).absolutePath)
    }

    private fun verifyIdentity(file: File) {
        ZipFile(file).use { zip ->
            val version = zip.getEntry("yt_dlp/version.py") ?: throw IOException("yt-dlp version metadata is missing")
            val ejs = zip.getEntry("yt_dlp_ejs/_version.py") ?: throw IOException("yt-dlp EJS metadata is missing")
            val versionText = zip.getInputStream(version).bufferedReader().use { it.readText() }
            val ejsText = zip.getInputStream(ejs).bufferedReader().use { it.readText() }
            if (!versionText.contains("__version__ = '$candidateVersion'") ||
                !ejsText.contains("__version__ = version = '$candidateEjsVersion'")
            ) throw IOException("yt-dlp candidate does not match the verified version pair")
        }
    }

    private fun copyBounded(input: InputStream, target: File) {
        FileOutputStream(target).use { output ->
            val bytes = ByteArray(8192)
            var total = 0L
            while (true) {
                val count = input.read(bytes)
                if (count < 0) break
                total += count
                if (total > maxBytes) throw IOException("yt-dlp candidate exceeds the size limit")
                output.write(bytes, 0, count)
            }
            output.fd.sync()
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
