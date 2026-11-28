// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.ActivityManager
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
class LifecycleRecoveryDeviceTest {
    @Test
    fun recentsRemovalPausesQueueAndStopsService() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val url = DeviceTestHelpers.decodeUrl("singleUrlB64")
        val (_, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        val id = DeviceTestHelpers.enqueue(
            instrumentation,
            view,
            url,
            "mp3",
            JSONObject().put("type", "audio").put("bitrate", 128),
            isPlaylist = false,
        )

        val deadline = SystemClock.elapsedRealtime() + 90_000
        var ready = false
        while (SystemClock.elapsedRealtime() < deadline) {
            val item = DeviceTestHelpers.queue(instrumentation, view).firstOrNull { it.optString("id") == id }
            val notice = DeviceTestHelpers.activeDownloadNotification(context)
            val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
            if (item?.optString("status") == "downloading" && notice != null && part != null && part.length() >= 8192) {
                Log.i(TAG, "RECENTS_REMOVING item=$id bytes=${part.length()}")
                ready = true
                break
            }
            Thread.sleep(200)
        }
        assertTrue("Active download with .part and foreground notification did not appear", ready)

        val task = context.getSystemService(ActivityManager::class.java).appTasks
            .firstOrNull { it.taskInfo.baseActivity?.packageName == context.packageName }
        assertTrue("App task missing from recents", task != null)
        task!!.finishAndRemoveTask()
        val cleanupDeadline = SystemClock.elapsedRealtime() + 10_000
        var stopped = false
        while (SystemClock.elapsedRealtime() < cleanupDeadline) {
            val notice = DeviceTestHelpers.activeDownloadNotification(context)
            val status = DeviceTestHelpers.readSqliteQueueStatus(context, id)
            val children = DeviceTestHelpers.descendants(instrumentation, Process.myPid())
            if (notice == null &&
                status == "paused" &&
                children.isEmpty() &&
                !AndroidEnginePlugin.hasActiveOperations()
            ) {
                stopped = true
                break
            }
            Thread.sleep(150)
        }
        assertTrue("Recents removal did not pause SQLite, clear notification, and stop children", stopped)
    }

    @Test
    fun verifyPausedAfterRecentsAndCleanUp() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val (activity, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        try {
            val items = DeviceTestHelpers.queue(instrumentation, view)
            assertEquals("Expected one paused item after recents removal", 1, items.size)
            val item = items.single()
            val id = item.getString("id")
            assertEquals("paused", item.getString("status"))
            assertEquals("paused", DeviceTestHelpers.readSqliteQueueStatus(context, id))

            Thread.sleep(3_000)
            val stillPaused = DeviceTestHelpers.queue(instrumentation, view).single()
            assertEquals("paused", stillPaused.getString("status"))
            Log.i(TAG, "RECENTS_REOPENED_PAUSED item=$id")

            DeviceTestHelpers.invoke(instrumentation, view, "remove_download", JSONObject().put("id", id))
            val removeDeadline = SystemClock.elapsedRealtime() + 20_000
            while (SystemClock.elapsedRealtime() < removeDeadline) {
                if (DeviceTestHelpers.queue(instrumentation, view).isEmpty()) break
                Thread.sleep(100)
            }
            assertTrue("Removed item stayed in queue", DeviceTestHelpers.queue(instrumentation, view).isEmpty())
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun startDownloadForProcessDeath() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val url = DeviceTestHelpers.decodeUrl("singleUrlB64")
        val (_, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        val id = DeviceTestHelpers.enqueue(
            instrumentation,
            view,
            url,
            "mp3",
            JSONObject().put("type", "audio").put("bitrate", 128),
            isPlaylist = false,
        )

        val deadline = SystemClock.elapsedRealtime() + 90_000
        while (SystemClock.elapsedRealtime() < deadline) {
            val item = DeviceTestHelpers.queue(instrumentation, view).firstOrNull { it.optString("id") == id }
            val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
            if (item?.optString("status") == "downloading" && part != null && part.length() >= 16_384) {
                Log.i(
                    TAG,
                    "PREKILL pid=${Process.myPid()} item=$id part=${part.name} bytes=${part.length()} prefix=${DeviceTestHelpers.prefixSha256(part)}",
                )
                // Host executes `am force-stop com.zownload.app` while sleeping.
                Thread.sleep(180_000)
                return
            }
            Thread.sleep(200)
        }
        throw AssertionError("Download never produced >=16 KiB .part file before kill")
    }

    @Test
    fun verifyProcessDeathRestoreAndContinue() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val (activity, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        var itemId: String? = null
        try {
            val items = DeviceTestHelpers.queue(instrumentation, view)
            assertEquals("Expected one interrupted item after process death", 1, items.size)
            val item = items.single()
            val id = item.getString("id")
            itemId = id
            val requestUrl = item.getJSONObject("request").getString("url")
            assertEquals("paused", item.getString("status"))
            assertEquals("paused", DeviceTestHelpers.readSqliteQueueStatus(context, id))

            val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
                ?: throw AssertionError("Saved .part missing after process death")
            val bytesBefore = part.length()
            val prefixBefore = DeviceTestHelpers.prefixSha256(part)
            assertTrue("Saved .part too small", bytesBefore >= 16_384)

            // Confirm interrupted item never auto-resumes.
            Thread.sleep(5_000)
            assertEquals("paused", DeviceTestHelpers.queue(instrumentation, view).single().getString("status"))
            assertEquals(bytesBefore, part.length())
            Log.i(TAG, "REOPENED_PAUSED item=$id bytes=$bytesBefore prefix=$prefixBefore idleMs=5000")

            val beforeMaxHistory = DeviceTestHelpers.maxHistoryId(DeviceTestHelpers.history(instrumentation, view))
            DeviceTestHelpers.invoke(instrumentation, view, "resume_download", JSONObject().put("id", id))

            val growthDeadline = SystemClock.elapsedRealtime() + 90_000
            var sawGrowth = false
            while (SystemClock.elapsedRealtime() < growthDeadline) {
                val now = DeviceTestHelpers.findPartFile(context.cacheDir, id)
                if (now != null && now.length() > bytesBefore + 8_192) {
                    assertEquals(prefixBefore, DeviceTestHelpers.prefixSha256(now))
                    Log.i(TAG, "CONTINUED_PART item=$id before=$bytesBefore after=${now.length()} prefix=$prefixBefore")
                    sawGrowth = true
                    break
                }
                if (DeviceTestHelpers.history(instrumentation, view).any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == requestUrl
                    }
                ) {
                    sawGrowth = true
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Saved .part did not resume after Continue", sawGrowth)

            val doneDeadline = SystemClock.elapsedRealtime() + 120_000
            var done = false
            while (SystemClock.elapsedRealtime() < doneDeadline) {
                if (DeviceTestHelpers.history(instrumentation, view).any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == requestUrl
                    } && DeviceTestHelpers.queue(instrumentation, view).isEmpty()
                ) {
                    done = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Continued download did not finish to History", done)
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
        private const val TAG = "Zownload5B05"
    }
}
