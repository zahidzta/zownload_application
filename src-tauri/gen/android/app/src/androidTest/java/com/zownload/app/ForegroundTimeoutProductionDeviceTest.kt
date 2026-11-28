// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Notification
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ForegroundTimeoutProductionDeviceTest {
    @Test
    fun android15SystemTimeoutPausesQueueAndPreservesPart() {
        assertTrue("System timeout test requires Android 15 (API 35+)", Build.VERSION.SDK_INT >= 35)
        runTimeoutFlow(triggerBySystemHome = true)
    }

    @Test
    fun simulatedTimeoutCallbackPausesQueueAndPreservesPart() {
        runTimeoutFlow(triggerBySystemHome = false)
    }

    private fun runTimeoutFlow(triggerBySystemHome: Boolean) {
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

            val activeDeadline = SystemClock.elapsedRealtime() + 90_000
            var partFile: java.io.File? = null
            while (SystemClock.elapsedRealtime() < activeDeadline) {
                val item = DeviceTestHelpers.queue(instrumentation, view).firstOrNull { it.optString("id") == id }
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
                if (item?.optString("status") == "downloading" &&
                    notice != null &&
                    part != null &&
                    part.length() >= 8192 &&
                    DownloadForegroundService.activeInstance != null
                ) {
                    partFile = part
                    break
                }
                Thread.sleep(200)
            }
            val partial = partFile ?: throw AssertionError("Active download with .part and foreground service never started")
            val bytesBefore = partial.length()
            val prefixBefore = DeviceTestHelpers.prefixSha256(partial)
            Log.i(TAG, "TIMEOUT_ACTIVE item=$id bytes=$bytesBefore prefix=$prefixBefore system=$triggerBySystemHome")

            instrumentation.uiAutomation.executeShellCommand("input keyevent KEYCODE_HOME").close()
            if (!triggerBySystemHome) {
                val service = DownloadForegroundService.activeInstance
                    ?: throw AssertionError("Live DownloadForegroundService missing before simulated callback")
                val fgsType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    0
                }
                instrumentation.runOnMainSync { service.handleForegroundTimeout(1, fgsType) }
            }

            val timeoutDeadline = SystemClock.elapsedRealtime() + 45_000
            var pausedOk = false
            while (SystemClock.elapsedRealtime() < timeoutDeadline) {
                val dbStatus = DeviceTestHelpers.readSqliteQueueStatus(context, id)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val noticeText = notice?.notification?.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                val children = DeviceTestHelpers.descendants(instrumentation, Process.myPid())
                if (dbStatus == "paused" &&
                    noticeText == DownloadForegroundService.DEFAULT_TIMEOUT_DETAIL &&
                    children.isEmpty() &&
                    !AndroidEnginePlugin.hasActiveOperations() &&
                    partial.isFile &&
                    partial.length() >= bytesBefore
                ) {
                    pausedOk = true
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Timeout did not pause SQLite, post detached notification, and stop children", pausedOk)

            val stableBytes = partial.length()
            Thread.sleep(3_000)
            assertEquals("Partial file changed while paused after timeout", stableBytes, partial.length())
            assertEquals(prefixBefore, DeviceTestHelpers.prefixSha256(partial))
            Log.i(TAG, "TIMEOUT_PAUSED item=$id bytes=$stableBytes prefix=$prefixBefore")

            val launch = instrumentation.uiAutomation.executeShellCommand(
                "am start -n com.zownload.app/.MainActivity -f 0x34000000"
            )
            val launchOutput = ParcelFileDescriptor.AutoCloseInputStream(launch)
                .bufferedReader().use { it.readText() }
            assertTrue("Could not bring MainActivity back: $launchOutput", launchOutput.contains("Starting:"))

            val restored = DeviceTestHelpers.queue(instrumentation, view).single()
            assertEquals(id, restored.getString("id"))
            assertEquals("paused", restored.getString("status"))
            Log.i(TAG, "TIMEOUT_REOPENED item=$id status=paused")

            // User explicitly presses Continue; preserved .part completes cleanly.
            DeviceTestHelpers.invoke(instrumentation, view, "resume_download", JSONObject().put("id", id))
            val doneDeadline = SystemClock.elapsedRealtime() + 120_000
            var done = false
            while (SystemClock.elapsedRealtime() < doneDeadline) {
                if (DeviceTestHelpers.history(instrumentation, view).any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == singleUrl
                    } && DeviceTestHelpers.queue(instrumentation, view).isEmpty()
                ) {
                    done = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Continued download after timeout did not complete", done)
            itemId = null
        } finally {
            itemId?.let { id ->
                try {
                    DeviceTestHelpers.invoke(instrumentation, view, "remove_download", JSONObject().put("id", id))
                } catch (_: Exception) {
                }
            }
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "long")
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "track-1")
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    companion object {
        private const val TAG = "Zownload5B07"
    }
}
