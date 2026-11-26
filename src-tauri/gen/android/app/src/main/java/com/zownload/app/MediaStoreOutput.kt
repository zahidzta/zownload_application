// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.system.ErrnoException
import android.system.OsConstants
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

internal data class PublishedMediaStoreOutput(
    val uri: String,
    val displayName: String,
    val mimeType: String,
    val bytes: Long,
)

internal fun chooseMediaStoreDisplayName(
    baseName: String,
    isTaken: (String) -> Boolean,
): String {
    if (!isTaken(baseName)) return baseName
    val dot = baseName.lastIndexOf('.')
    val stem = if (dot > 0) baseName.substring(0, dot) else baseName
    val extension = if (dot > 0) baseName.substring(dot) else ""
    var suffix = 1
    while (true) {
        val candidate = "$stem ($suffix)$extension"
        if (!isTaken(candidate)) return candidate
        if (suffix == Int.MAX_VALUE) throw IOException("No available Downloads filename remains")
        suffix += 1
    }
}

internal fun publishMediaStoreOutput(
    context: Context,
    source: File,
    displayName: String,
    format: String,
): PublishedMediaStoreOutput {
    if (!source.isFile || source.length() == 0L) {
        throw EngineBridgeException("engine_missing", "Android engine output is missing or empty")
    }
    return publishMediaStoreOutput(context, source.length(), { source.inputStream() }, displayName, format)
}

// This overload keeps the copy failure path directly testable with a stream
// that fails after a partial write, while production only passes an app file.
internal fun publishMediaStoreOutput(
    context: Context,
    sourceBytes: Long,
    openSource: () -> InputStream,
    displayName: String,
    format: String,
): PublishedMediaStoreOutput {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        throw EngineBridgeException("engine_missing", "MediaStore Downloads output requires Android 10 or newer")
    }
    val (extension, mimeType) = when (format) {
        "mp3" -> "mp3" to "audio/mpeg"
        "mp4" -> "mp4" to "video/mp4"
        else -> throw EngineBridgeException("engine_missing", "Unsupported Android output format")
    }
    if (!isSafeDisplayName(displayName, extension) || sourceBytes <= 0L) {
        throw EngineBridgeException("engine_missing", "Invalid Android output name or size")
    }

    val resolver = context.contentResolver
    val downloads = MediaStore.Downloads.EXTERNAL_CONTENT_URI
    val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/"
    val safeName = try {
        chooseMediaStoreDisplayName(displayName) { candidate ->
            resolver.query(
                downloads,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
                arrayOf(candidate, relativePath),
                null,
            )?.use(Cursor::moveToFirst) ?: throw IOException("MediaStore could not check Downloads filenames")
        }
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }

    val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, safeName)
        put(MediaStore.Downloads.MIME_TYPE, mimeType)
        put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
        put(MediaStore.Downloads.IS_PENDING, 1)
    }
    val uri = try {
        resolver.insert(downloads, values)
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    } ?: throw EngineBridgeException("unknown", "MediaStore refused to create a Downloads item")

    try {
        var copied = 0L
        val output = resolver.openOutputStream(uri, "w")
            ?: throw IOException("MediaStore could not open the pending Downloads item")
        output.use { target ->
            openSource().use { input -> copied = copyAndCount(input, target) }
        }
        if (copied != sourceBytes) throw IOException("MediaStore output size does not match the engine result")

        val pending = resolver.query(
            uri,
            arrayOf(
                MediaStore.Downloads.DISPLAY_NAME,
                MediaStore.Downloads.MIME_TYPE,
                MediaStore.Downloads.IS_PENDING,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            cursor.moveToFirst() &&
                cursor.getString(0) == safeName &&
                cursor.getString(1) == mimeType &&
                cursor.getInt(2) == 1
        } ?: false
        if (!pending) throw IOException("MediaStore pending item metadata does not match the request")

        val visible = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        if (resolver.update(uri, visible, null, null) != 1) {
            throw IOException("MediaStore could not publish the completed Downloads item")
        }
        return PublishedMediaStoreOutput(uri.toString(), safeName, mimeType, copied)
    } catch (error: Exception) {
        try {
            resolver.delete(uri, null, null)
        } catch (cleanup: Exception) {
            error.addSuppressed(cleanup)
        }
        throw mapMediaStoreFailure(error)
    }
}

private fun isSafeDisplayName(name: String, extension: String): Boolean =
    name.endsWith(".$extension") &&
        name.isNotBlank() &&
        name.length <= 255 &&
        name != "." &&
        name != ".." &&
        name.none { it.isISOControl() || it in "<>:\"/\\|?*" }

private fun copyAndCount(input: InputStream, output: OutputStream): Long {
    val buffer = ByteArray(32 * 1024)
    var total = 0L
    while (true) {
        val count = input.read(buffer)
        if (count < 0) return total
        output.write(buffer, 0, count)
        total += count
    }
}

private fun mapMediaStoreFailure(error: Exception): EngineBridgeException {
    if (error is EngineBridgeException) return error
    var cause: Throwable? = error
    while (cause != null) {
        if (cause is SecurityException) {
            return EngineBridgeException("permission_denied", error.message ?: "MediaStore permission denied")
        }
        if (cause is ErrnoException) {
            when (cause.errno) {
                OsConstants.ENOSPC -> return EngineBridgeException("disk_full", error.message ?: "Downloads storage is full")
                OsConstants.EACCES, OsConstants.EPERM, OsConstants.EROFS ->
                    return EngineBridgeException("permission_denied", error.message ?: "MediaStore permission denied")
            }
        }
        cause = cause.cause
    }
    return EngineBridgeException("unknown", error.message ?: error.javaClass.simpleName)
}
