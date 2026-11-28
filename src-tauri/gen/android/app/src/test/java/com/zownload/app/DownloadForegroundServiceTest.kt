// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadForegroundServiceTest {
    @Test
    fun activeNotificationContentClampsProgressAndPreservesTitle() {
        val content = formatNotificationContent(
            title = "Sample Track",
            detail = "42%",
            percent = 140,
            indeterminate = false,
            ongoing = true,
        )
        assertEquals("Sample Track", content.title)
        assertEquals("42%", content.text)
        assertEquals(100, content.percent)
        assertFalse(content.indeterminate)
        assertTrue(content.ongoing)
    }

    @Test
    fun timeoutNotificationContentDefaultsAndIsNotOngoing() {
        val content = formatNotificationContent(
            title = "",
            detail = DownloadForegroundService.DEFAULT_TIMEOUT_DETAIL,
            percent = -5,
            indeterminate = false,
            ongoing = false,
        )
        assertEquals("Zownload", content.title)
        assertEquals("Downloads paused. Open Zownload to continue.", content.text)
        assertEquals(0, content.percent)
        assertFalse(content.ongoing)
    }

    @Test
    fun zipDisplayNamesResolveCollisionsWithoutOverwriting() {
        val selected = chooseMediaStoreDisplayName("Mix.zip") { candidate ->
            candidate == "Mix.zip" || candidate == "Mix (1).zip"
        }
        assertEquals("Mix (2).zip", selected)
    }

    @Test
    fun notificationUpdatesDeduplicateIdenticalProgressSnapshots() {
        val initial = formatNotificationContent(
            title = "Sample Track",
            detail = "15%",
            percent = 15,
            indeterminate = false,
            ongoing = true,
        )
        val identical = formatNotificationContent(
            title = "Sample Track",
            detail = "15%",
            percent = 15,
            indeterminate = false,
            ongoing = true,
        )
        val nextPercent = formatNotificationContent(
            title = "Sample Track",
            detail = "16%",
            percent = 16,
            indeterminate = false,
            ongoing = true,
        )
        assertTrue(shouldPostNotificationUpdate(null, initial))
        assertFalse(shouldPostNotificationUpdate(initial, identical))
        assertTrue(shouldPostNotificationUpdate(initial, nextPercent))
    }

    @Test
    fun mediaStorePublishedDisplayNameAcceptsExactAndScopedStorageNumberedCollisions() {
        assertTrue(isExpectedPublishedDisplayName("track.mp3", "track.mp3", "mp3"))
        assertTrue(isExpectedPublishedDisplayName("track.mp3", "track (1).mp3", "mp3"))
        assertTrue(isExpectedPublishedDisplayName("track.mp3", "track (12).mp3", "mp3"))
        assertFalse(isExpectedPublishedDisplayName("track.mp3", "track (0).mp3", "mp3"))
        assertFalse(isExpectedPublishedDisplayName("track.mp3", "track (abc).mp3", "mp3"))
        assertFalse(isExpectedPublishedDisplayName("track.mp3", "other (1).mp3", "mp3"))
        assertFalse(isExpectedPublishedDisplayName("track.mp3", "track (1).mp4", "mp3"))
    }

    @Test
    fun insertFallbackRetriesWithNumberedCandidatesWhenMediaStoreReturnsNull() {
        val tried = mutableListOf<String>()
        val result = insertWithNumberedFallback("track.mp3") { candidate ->
            tried += candidate
            if (candidate == "track (2).mp3") "content://media/external/downloads/99" else null
        }
        assertEquals(listOf("track.mp3", "track (1).mp3", "track (2).mp3"), tried)
        assertEquals("track (2).mp3" to "content://media/external/downloads/99", result)
    }
}
