// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.UUID
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaStoreSingleOutputDeviceTest {
    @Test
    fun mp3AndMp4ArePublishedWithNumberedCollisionsAndNoPartialRows() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val token = UUID.randomUUID().toString()
        val resolver = context.contentResolver
        val mp3Bytes = byteArrayOf(1, 3, 5, 7, 9)
        val mp4Bytes = byteArrayOf(2, 4, 6, 8, 10)
        val mp3Source = sourceFile(context, token, mp3Bytes)
        val mp4Source = sourceFile(context, "$token-video", mp4Bytes)
        val publishedUris = mutableListOf<android.net.Uri>()
        try {
            val mp3Base = "Zownload 5B02 $token.mp3"
            val first = publishMediaStoreOutput(context, mp3Source, mp3Base, "mp3")
            val second = publishMediaStoreOutput(context, mp3Source, mp3Base, "mp3")
            publishedUris += android.net.Uri.parse(first.uri)
            publishedUris += android.net.Uri.parse(second.uri)
            assertEquals(mp3Base, first.displayName)
            assertEquals("Zownload 5B02 $token (1).mp3", second.displayName)
            assertPublished(context, first.uri, mp3Base, "audio/mpeg", mp3Bytes)
            assertPublished(context, second.uri, second.displayName, "audio/mpeg", mp3Bytes)

            val mp4Base = "Zownload 5B02 $token.mp4"
            val mp4 = publishMediaStoreOutput(context, mp4Source, mp4Base, "mp4")
            publishedUris += android.net.Uri.parse(mp4.uri)
            assertPublished(context, mp4.uri, mp4Base, "video/mp4", mp4Bytes)

            val failedName = "Zownload 5B02 $token-failed.mp4"
            try {
                publishMediaStoreOutput(context, 100L, {
                    object : InputStream() {
                        private var sent = false
                        override fun read(): Int = throw IOException("injected MediaStore copy failure")
                        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                            if (sent) throw IOException("injected MediaStore copy failure")
                            sent = true
                            val partial = byteArrayOf(11, 12, 13)
                            partial.copyInto(buffer, offset, 0, minOf(length, partial.size))
                            return minOf(length, partial.size)
                        }
                    }
                }, failedName, "mp4")
                throw AssertionError("Expected the injected MediaStore copy failure")
            } catch (error: EngineBridgeException) {
                assertEquals("unknown", error.code)
            }
            assertEquals(0, countByName(context, failedName))
        } finally {
            publishedUris.forEach { resolver.delete(it, null, null) }
            mp3Source.delete()
            mp4Source.delete()
        }
    }

    private fun sourceFile(context: Context, suffix: String, bytes: ByteArray): File =
        File(context.cacheDir, "gate-5b02-$suffix.bin").apply { writeBytes(bytes) }

    private fun assertPublished(
        context: Context,
        uriText: String,
        expectedName: String,
        expectedMime: String,
        expectedBytes: ByteArray,
    ) {
        val resolver = context.contentResolver
        resolver.query(
            android.net.Uri.parse(uriText),
            arrayOf(
                MediaStore.Downloads.DISPLAY_NAME,
                MediaStore.Downloads.MIME_TYPE,
                MediaStore.Downloads.RELATIVE_PATH,
                MediaStore.Downloads.IS_PENDING,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals(expectedName, cursor.getString(0))
            assertEquals(expectedMime, cursor.getString(1))
            assertEquals("${Environment.DIRECTORY_DOWNLOADS}/", cursor.getString(2))
            assertEquals(0, cursor.getInt(3))
        } ?: throw AssertionError("Published Downloads row could not be queried")
        val actual = resolver.openInputStream(android.net.Uri.parse(uriText))?.use { it.readBytes() }
            ?: throw AssertionError("Published Downloads row could not be opened")
        assertArrayEquals(expectedBytes, actual)
    }

    private fun countByName(context: Context, displayName: String): Int =
        context.contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
            arrayOf(displayName, "${Environment.DIRECTORY_DOWNLOADS}/"),
            null,
        )?.use { it.count } ?: throw AssertionError("Downloads rows could not be queried")
}
