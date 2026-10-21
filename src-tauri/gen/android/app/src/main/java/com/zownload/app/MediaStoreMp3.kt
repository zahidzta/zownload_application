// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.IOException
import java.security.MessageDigest

internal data class PublishedMp3(
    val uri: String,
    val displayName: String,
    val mimeType: String,
    val sha256: String,
    val bytes: Long,
)

internal fun publishMp3(context: Context, source: File, displayName: String): PublishedMp3 {
    if (Build.VERSION.SDK_INT < 29) throw IOException("MediaStore Downloads pending rows require API 29")
    if (!source.isFile || source.length() == 0L) throw IOException("Converted MP3 is missing or empty")
    val resolver = context.contentResolver
    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, displayName)
        put(MediaStore.Downloads.MIME_TYPE, "audio/mpeg")
        put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/")
        put(MediaStore.Downloads.IS_PENDING, 1)
    }
    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        ?: throw IOException("MediaStore refused to create a Downloads row")
    var published = false
    try {
        val digest = MessageDigest.getInstance("SHA-256")
        var bytes = 0L
        resolver.openOutputStream(uri, "w")?.use { target ->
            source.inputStream().use { input ->
                val chunk = ByteArray(8192)
                while (true) {
                    val count = input.read(chunk)
                    if (count < 0) break
                    target.write(chunk, 0, count)
                    digest.update(chunk, 0, count)
                    bytes += count
                }
            }
        } ?: throw IOException("MediaStore could not open the pending row")
        if (bytes != source.length()) throw IOException("MediaStore copy length mismatch")
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        val visible = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        if (resolver.update(uri, visible, null, null) != 1) throw IOException("MediaStore publish failed")
        published = true
        resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME, MediaStore.Downloads.MIME_TYPE, MediaStore.Downloads.IS_PENDING),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst() ||
                cursor.getString(0) != displayName ||
                cursor.getString(1) != "audio/mpeg" ||
                cursor.getInt(2) != 0
            ) throw IOException("Published MediaStore metadata differs from the requested row")
        } ?: throw IOException("Published MediaStore row cannot be queried")
        // Read through the published content URI, not the private source file.
        val actual = MessageDigest.getInstance("SHA-256")
        resolver.openInputStream(uri)?.use { stream ->
            val chunk = ByteArray(8192)
            while (true) {
                val count = stream.read(chunk)
                if (count < 0) break
                actual.update(chunk, 0, count)
            }
        } ?: throw IOException("Published MediaStore row cannot be opened")
        val actualHash = actual.digest().joinToString("") { "%02x".format(it) }
        if (actualHash != hash) throw IOException("Published MediaStore row hash mismatch")
        return PublishedMp3(uri.toString(), displayName, "audio/mpeg", hash, bytes)
    } catch (error: Exception) {
        // A failed copy must never leave an invisible row behind.
        try {
            val deleted = resolver.delete(uri, null, null)
            Log.w("Zownload0C06", "Failed publish row cleanup uri=$uri deleted=$deleted published=$published")
        } catch (cleanup: Exception) {
            Log.e("Zownload0C06", "Failed publish row cleanup uri=$uri", cleanup)
            error.addSuppressed(cleanup)
        }
        throw error
    }
}
