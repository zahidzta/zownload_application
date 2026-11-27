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
}
