// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.net.Uri
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaStoreZipOutputDeviceTest {
    @Test
    fun pendingMediaStoreZipSupportsSeekableRwCollisionsAndCleanup() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val resolver = context.contentResolver
        val token = UUID.randomUUID().toString()
        val baseName = "Zownload 5B03 $token.zip"
        val uris = mutableListOf<Uri>()
        try {
            val pending1 = createPendingMediaStoreZip(context, baseName)
            val uri1 = Uri.parse(pending1.uri)
            uris += uri1
            assertEquals(baseName, pending1.displayName)

            val tempZip = File(context.cacheDir, "gate-5b03-$token.zip")
            try {
                ZipOutputStream(FileOutputStream(tempZip)).use { zos ->
                    zos.setMethod(ZipOutputStream.STORED)
                    val payload = "5b03-payload".toByteArray()
                    val entry = ZipEntry("sample.mp3").apply {
                        size = payload.size.toLong()
                        compressedSize = payload.size.toLong()
                        crc = java.util.zip.CRC32().apply { update(payload) }.value
                    }
                    zos.putNextEntry(entry)
                    zos.write(payload)
                    zos.closeEntry()
                }
                val expectedBytes = tempZip.readBytes()
                val fd1 = openPendingMediaStoreZipFd(context, pending1.uri)
                ParcelFileDescriptor.adoptFd(fd1).use { pfd ->
                    FileOutputStream(pfd.fileDescriptor).use { out ->
                        out.write(expectedBytes)
                        out.fd.sync()
                    }
                }
                // Reopen rw fd to verify MediaStore allows seeking/resume across handles.
                val fdReopened = openPendingMediaStoreZipFd(context, pending1.uri)
                ParcelFileDescriptor.adoptFd(fdReopened).use { pfd ->
                    assertTrue(pfd.statSize == expectedBytes.size.toLong())
                }

                val pending2 = createPendingMediaStoreZip(context, baseName)
                val uri2 = Uri.parse(pending2.uri)
                uris += uri2
                assertEquals("Zownload 5B03 $token (1).zip", pending2.displayName)
                assertEquals(1, deletePendingMediaStoreZip(context, pending2.uri))
                uris.remove(uri2)

                val published = publishPendingMediaStoreZip(context, pending1.uri, expectedBytes.size.toLong())
                assertEquals(baseName, published.displayName)
                assertEquals("application/zip", published.mimeType)

                resolver.query(
                    uri1,
                    arrayOf(MediaStore.Downloads.IS_PENDING, MediaStore.Downloads.MIME_TYPE),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(0, cursor.getInt(0))
                    assertEquals("application/zip", cursor.getString(1))
                } ?: throw AssertionError("Published ZIP row missing")

                val verifyCopy = File(context.cacheDir, "gate-5b03-readback-$token.zip")
                try {
                    resolver.openInputStream(uri1)!!.use { input ->
                        verifyCopy.outputStream().use { output -> input.copyTo(output) }
                    }
                    ZipFile(verifyCopy).use { zf ->
                        val entry = zf.getEntry("sample.mp3")!!
                        assertEquals(ZipEntry.STORED, entry.method)
                        assertEquals("5b03-payload", zf.getInputStream(entry).readBytes().decodeToString())
                    }
                } finally {
                    verifyCopy.delete()
                }
            } finally {
                tempZip.delete()
            }
        } finally {
            uris.forEach { resolver.delete(it, null, null) }
        }
    }

    @Test
    fun playlistZipDownloadsEndToEndThroughMediaStoreWithZeroLeftoverWorkFiles() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val playlistUrl = DeviceTestHelpers.decodeUrl("playlistUrlB64")
        val (activity, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        var originalSettings: JSONObject? = null
        try {
            originalSettings = JSONObject(DeviceTestHelpers.invoke(instrumentation, view, "get_settings"))
            val zipSettings = JSONObject(originalSettings.toString()).put("zipPlaylists", true)
            DeviceTestHelpers.invoke(instrumentation, view, "set_settings", JSONObject().put("settings", zipSettings))

            val beforeMaxHistory = DeviceTestHelpers.maxHistoryId(DeviceTestHelpers.history(instrumentation, view))
            val id = DeviceTestHelpers.enqueue(
                instrumentation,
                view,
                playlistUrl,
                "mp3",
                JSONObject().put("type", "max"),
                isPlaylist = true,
            )

            val deadline = SystemClock.elapsedRealtime() + 180_000
            var completed = false
            while (SystemClock.elapsedRealtime() < deadline) {
                val queue = DeviceTestHelpers.queue(instrumentation, view)
                val item = queue.firstOrNull { it.optString("id") == id }
                if (item?.optString("status") == "failed") {
                    throw AssertionError("Playlist ZIP failed: ${item.optJSONObject("error")}")
                }
                val history = DeviceTestHelpers.history(instrumentation, view)
                if (history.any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == playlistUrl
                    }
                ) {
                    assertTrue(queue.none { it.optString("id") == id })
                    completed = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Playlist ZIP did not complete in time", completed)

            // Verify zero leftover entry directories or ZIP journals.
            val engineCache = File(context.cacheDir, "zownload-engine")
            val leftovers = engineCache.listFiles()?.filter { it.name == id || it.name.startsWith("${id}_") }.orEmpty()
            assertTrue("Leftover engine work files found: $leftovers", leftovers.isEmpty())
            assertFalse(File(context.filesDir, "android-zip/$id").exists())

            val publishedUris = DeviceTestHelpers.findDownloadsByTitlePrefix(context, "Zownload Gate 5B Mix")
            assertEquals("Expected one published playlist ZIP in Downloads", 1, publishedUris.size)
            val verifyCopy = File(context.cacheDir, "verify-e2e-$id.zip")
            try {
                context.contentResolver.openInputStream(publishedUris.single())!!.use { input ->
                    verifyCopy.outputStream().use { output -> input.copyTo(output) }
                }
                ZipFile(verifyCopy).use { zf ->
                    val entries = zf.entries().toList()
                    assertEquals(2, entries.size)
                    assertEquals(listOf("fixture.mp3", "fixture (1).mp3"), entries.map { it.name })
                    assertTrue(entries.all { it.method == ZipEntry.STORED && it.size > 1_000 })
                }
            } finally {
                verifyCopy.delete()
            }
        } finally {
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "Zownload Gate 5B Mix")
            originalSettings?.let {
                try {
                    DeviceTestHelpers.invoke(instrumentation, view, "set_settings", JSONObject().put("settings", it))
                } catch (_: Exception) {
                }
            }
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
