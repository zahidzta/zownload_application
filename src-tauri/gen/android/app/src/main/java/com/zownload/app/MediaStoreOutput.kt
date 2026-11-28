// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.system.ErrnoException
import android.system.OsConstants
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

internal data class PublishedMediaStoreOutput(
    val uri: String,
    val displayName: String,
    val mimeType: String,
    val bytes: Long,
)

internal data class PendingMediaStoreZip(
    val uri: String,
    val displayName: String,
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

    val (insertedName, uri) = try {
        insertWithNumberedFallback(safeName) { candidate ->
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, candidate)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            resolver.insert(downloads, values)
        }
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

        var actualName: String? = null
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
            if (!cursor.moveToFirst()) return@use false
            actualName = cursor.getString(0)
            actualName != null &&
                isExpectedPublishedDisplayName(insertedName, actualName!!, extension) &&
                cursor.getString(1) == mimeType &&
                cursor.getInt(2) == 1
        } ?: false
        if (!pending) throw IOException("MediaStore pending item metadata does not match the request")

        val visible = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        if (resolver.update(uri, visible, null, null) != 1) {
            throw IOException("MediaStore could not publish the completed Downloads item")
        }
        return PublishedMediaStoreOutput(uri.toString(), actualName!!, mimeType, copied)
    } catch (error: Exception) {
        try {
            resolver.delete(uri, null, null)
        } catch (cleanup: Exception) {
            error.addSuppressed(cleanup)
        }
        throw mapMediaStoreFailure(error)
    }
}

internal fun createPendingMediaStoreZip(
    context: Context,
    displayName: String,
): PendingMediaStoreZip {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        throw EngineBridgeException("engine_missing", "MediaStore Downloads output requires Android 10 or newer")
    }
    if (!isSafeDisplayName(displayName, "zip")) {
        throw EngineBridgeException("engine_missing", "Invalid Android ZIP output name")
    }
    val resolver = context.contentResolver
    val downloads = MediaStore.Downloads.EXTERNAL_CONTENT_URI
    val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/"
    val safeName = try {
        chooseMediaStoreDisplayName(displayName) { candidate ->
            queryDisplayNameExists(resolver, downloads, candidate, relativePath, excludeId = null)
        }
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
    val (insertedName, uri) = try {
        insertWithNumberedFallback(safeName) { candidate ->
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, candidate)
                put(MediaStore.Downloads.MIME_TYPE, "application/zip")
                put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            resolver.insert(downloads, values)
        }
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    } ?: throw EngineBridgeException("unknown", "MediaStore refused to create a pending ZIP row")
    return PendingMediaStoreZip(uri.toString(), insertedName)
}

internal fun openPendingMediaStoreZipFd(
    context: Context,
    uriText: String,
): Int {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        throw EngineBridgeException("engine_missing", "MediaStore Downloads output requires Android 10 or newer")
    }
    val uri = parseOwnedPendingDownloadsUri(uriText)
    val resolver = context.contentResolver
    val isPending = try {
        resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.IS_PENDING),
            null,
            null,
            null,
        )?.use { cursor ->
            cursor.moveToFirst() && cursor.getInt(0) == 1
        } ?: false
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
    if (!isPending) {
        throw EngineBridgeException("engine_missing", "Pending MediaStore ZIP row is missing or already published")
    }
    val pfd = try {
        resolver.openFileDescriptor(uri, "rw")
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    } ?: throw EngineBridgeException("unknown", "MediaStore could not open the pending ZIP file descriptor")
    return pfd.detachFd()
}

internal fun publishPendingMediaStoreZip(
    context: Context,
    uriText: String,
    expectedBytes: Long,
): PublishedMediaStoreOutput {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        throw EngineBridgeException("engine_missing", "MediaStore Downloads output requires Android 10 or newer")
    }
    if (expectedBytes <= 0L) {
        throw EngineBridgeException("engine_missing", "Pending Android ZIP output is empty")
    }
    val uri = parseOwnedPendingDownloadsUri(uriText)
    val resolver = context.contentResolver
    val downloads = MediaStore.Downloads.EXTERNAL_CONTENT_URI
    val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/"

    val (rowId, currentName, isPending) = try {
        resolver.query(
            uri,
            arrayOf(
                MediaStore.Downloads._ID,
                MediaStore.Downloads.DISPLAY_NAME,
                MediaStore.Downloads.IS_PENDING,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) null
            else Triple(cursor.getLong(0), cursor.getString(1), cursor.getInt(2))
        } ?: throw EngineBridgeException("engine_missing", "Pending MediaStore ZIP row is missing")
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
    if (isPending != 1 || !isSafeDisplayName(currentName, "zip")) {
        throw EngineBridgeException("engine_missing", "MediaStore ZIP row is not pending or has an invalid name")
    }

    val actualBytes = try {
        resolver.openFileDescriptor(uri, "r")?.use { pfd ->
            if (pfd.statSize >= 0L) pfd.statSize
            else FileInputStream(pfd.fileDescriptor).channel.size()
        } ?: throw IOException("MediaStore could not inspect the pending ZIP size")
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
    if (actualBytes != expectedBytes) {
        throw EngineBridgeException("unknown", "MediaStore ZIP size does not match the committed archive")
    }

    val finalName = try {
        chooseMediaStoreDisplayName(currentName) { candidate ->
            queryDisplayNameExists(resolver, downloads, candidate, relativePath, excludeId = rowId)
        }
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }

    val visible = ContentValues().apply {
        put(MediaStore.Downloads.IS_PENDING, 0)
        if (finalName != currentName) {
            put(MediaStore.Downloads.DISPLAY_NAME, finalName)
        }
    }
    val updated = try {
        resolver.update(uri, visible, null, null)
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
    if (updated != 1) {
        throw EngineBridgeException("unknown", "MediaStore could not publish the completed ZIP item")
    }
    return PublishedMediaStoreOutput(uri.toString(), finalName, "application/zip", actualBytes)
}

internal fun deletePendingMediaStoreZip(
    context: Context,
    uriText: String,
): Int {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
    val uri = parseOwnedPendingDownloadsUri(uriText)
    return try {
        context.contentResolver.delete(uri, null, null)
    } catch (error: Exception) {
        throw mapMediaStoreFailure(error)
    }
}

internal fun deleteOperationWorkDir(cacheDir: File, operationId: String): Boolean {
    if (!Regex("^[A-Za-z0-9_-]{1,64}$").matches(operationId)) {
        throw EngineBridgeException("permission_denied", "Invalid Android engine operation ID")
    }
    val root = File(cacheDir, "zownload-engine").canonicalFile
    val target = File(root, operationId).canonicalFile
    if (!target.path.startsWith(root.path + File.separator)) {
        throw EngineBridgeException("permission_denied", "Operation directory is outside engine cache")
    }
    return if (target.exists()) target.deleteRecursively() else true
}

internal fun deleteQueueCacheDirs(cacheDir: File, queueId: String): Boolean {
    if (!Regex("^[a-fA-F0-9-]{36}$").matches(queueId)) {
        throw EngineBridgeException("permission_denied", "Invalid Android queue ID")
    }
    val root = File(cacheDir, "zownload-engine").canonicalFile
    val children = root.listFiles() ?: return true
    var deletedAll = true
    for (child in children) {
        if (child.name == queueId || child.name.startsWith("${queueId}_")) {
            val canonical = child.canonicalFile
            if (canonical.path.startsWith(root.path + File.separator) && !canonical.deleteRecursively()) {
                deletedAll = false
            }
        }
    }
    return deletedAll
}

private fun queryDisplayNameExists(
    resolver: android.content.ContentResolver,
    downloads: Uri,
    candidate: String,
    relativePath: String,
    excludeId: Long?,
): Boolean {
    val selection = if (excludeId != null) {
        "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ? AND ${MediaStore.Downloads._ID} != ?"
    } else {
        "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?"
    }
    val args = if (excludeId != null) {
        arrayOf(candidate, relativePath, excludeId.toString())
    } else {
        arrayOf(candidate, relativePath)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val queryArgs = Bundle().apply {
            putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
            putStringArray(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
            putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
        }
        return resolver.query(
            downloads,
            arrayOf(MediaStore.Downloads._ID),
            queryArgs,
            null,
        )?.use(Cursor::moveToFirst) ?: throw IOException("MediaStore could not check Downloads filenames")
    }
    @Suppress("DEPRECATION")
    val queryUri = MediaStore.setIncludePending(downloads)
    return resolver.query(
        queryUri,
        arrayOf(MediaStore.Downloads._ID),
        selection,
        args,
        null,
    )?.use(Cursor::moveToFirst) ?: throw IOException("MediaStore could not check Downloads filenames")
}

private fun parseOwnedPendingDownloadsUri(uriText: String): Uri {
    if (!uriText.startsWith("content://media/")) {
        throw EngineBridgeException("permission_denied", "Invalid MediaStore Downloads URI")
    }
    return Uri.parse(uriText)
}

internal fun <T> insertWithNumberedFallback(
    initialName: String,
    maxAttempts: Int = 64,
    tryInsert: (String) -> T?,
): Pair<String, T>? {
    val dot = initialName.lastIndexOf('.')
    val stem = if (dot > 0) initialName.substring(0, dot) else initialName
    val extension = if (dot > 0) initialName.substring(dot) else ""
    var candidate = initialName
    var suffix = 1
    repeat(maxAttempts) {
        val created = tryInsert(candidate)
        if (created != null) return candidate to created
        candidate = "$stem ($suffix)$extension"
        suffix += 1
    }
    return null
}

internal fun isExpectedPublishedDisplayName(
    requestedName: String,
    actualName: String,
    extension: String,
): Boolean {
    if (!isSafeDisplayName(actualName, extension)) return false
    if (actualName == requestedName) return true
    val suffix = ".$extension"
    val stem = requestedName.removeSuffix(suffix)
    if (!actualName.startsWith("$stem (") || !actualName.endsWith(")$suffix")) return false
    val number = actualName.substring(stem.length + 2, actualName.length - suffix.length - 1)
    return number.isNotEmpty() && number.all(Char::isDigit) && number.toIntOrNull()?.let { it >= 1 } == true
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
