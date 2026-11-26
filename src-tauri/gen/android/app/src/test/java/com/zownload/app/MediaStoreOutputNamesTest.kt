// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaStoreOutputNamesTest {
    @Test
    fun collisionNamesAppendNumberBeforeTheExtension() {
        val checked = mutableListOf<String>()
        val selected = chooseMediaStoreDisplayName("song.mp4") { candidate ->
            checked += candidate
            candidate == "song.mp4" || candidate == "song (1).mp4"
        }

        assertEquals("song (2).mp4", selected)
        assertEquals(listOf("song.mp4", "song (1).mp4", "song (2).mp4"), checked)
    }

    @Test
    fun firstAvailableNameDoesNotGetRenamed() {
        assertEquals("song.mp3", chooseMediaStoreDisplayName("song.mp3") { false })
    }
}
