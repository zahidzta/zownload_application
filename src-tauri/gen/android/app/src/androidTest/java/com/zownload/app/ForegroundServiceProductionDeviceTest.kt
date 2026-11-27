// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Notification
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ForegroundServiceProductionDeviceTest {
    @Test
    fun dataSyncServiceStartsShowsProgressStopsOnPauseAndIdleWithZeroActions() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val singleUrl = DeviceTestHelpers.decodeUrl("singleUrlB64")
        val (activity, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        var itemId: String? = null
        try {
            val beforeMaxHistory = DeviceTestHelpers.maxHistoryId(DeviceTestHelpers.history(instrumentation, view))
            val id = DeviceTestHelpers.enqueue(
                instrumentation,
                view,
                singleUrl,
                "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                isPlaylist = false,
            )
            itemId = id

            // Wait for active downloading + .part + ongoing progress notification without action buttons.
            val activeDeadline = SystemClock.elapsedRealtime() + 90_000
            var sawNotification = false
            while (SystemClock.elapsedRealtime() < activeDeadline) {
                val item = DeviceTestHelpers.queue(instrumentation, view).firstOrNull { it.optString("id") == id }
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
                if (item?.optString("status") == "downloading" && notice != null && part != null && part.length() >= 4096) {
                    val notification = notice.notification
                    assertTrue(
                        "Progress notification must be ongoing",
                        (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0,
                    )
                    assertTrue(
                        "Progress notification must have no action buttons",
                        notification.actions == null || notification.actions.isEmpty(),
                    )
                    sawNotification = true
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Foreground service notification never appeared while downloading", sawNotification)

            // Pause and confirm the service + notification stop.
            DeviceTestHelpers.invoke(instrumentation, view, "pause_download", JSONObject().put("id", id))
            val pauseDeadline = SystemClock.elapsedRealtime() + 30_000
            var paused = false
            while (SystemClock.elapsedRealtime() < pauseDeadline) {
                val item = DeviceTestHelpers.queue(instrumentation, view).firstOrNull { it.optString("id") == id }
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                if (item?.optString("status") == "paused" && notice == null) {
                    paused = true
                    break
                }
                Thread.sleep(150)
            }
            assertTrue("Pausing did not transition to paused and stop the service", paused)

            // Resume and wait for completion; service starts again and stops when idle.
            DeviceTestHelpers.invoke(instrumentation, view, "resume_download", JSONObject().put("id", id))
            val resumeDeadline = SystemClock.elapsedRealtime() + 30_000
            var restartedNotice = false
            while (SystemClock.elapsedRealtime() < resumeDeadline) {
                if (DeviceTestHelpers.activeDownloadNotification(context) != null) {
                    restartedNotice = true
                    break
                }
                Thread.sleep(100)
            }
            assertTrue("Resuming did not restart the foreground notification", restartedNotice)

            val doneDeadline = SystemClock.elapsedRealtime() + 120_000
            var done = false
            while (SystemClock.elapsedRealtime() < doneDeadline) {
                val history = DeviceTestHelpers.history(instrumentation, view)
                val queue = DeviceTestHelpers.queue(instrumentation, view)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                if (history.any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == singleUrl
                    } && queue.none { it.optString("id") == id } && notice == null
                ) {
                    done = true
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Completed item did not settle and stop the foreground service", done)
            assertEquals(0, DeviceTestHelpers.queue(instrumentation, view).size)
            itemId = null
        } finally {
            itemId?.let { id ->
                try {
                    DeviceTestHelpers.invoke(instrumentation, view, "remove_download", JSONObject().put("id", id))
                } catch (_: Exception) {
                }
            }
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "track-1")
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "long")
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
