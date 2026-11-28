// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.app.Application
import android.app.Notification
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HomeAndRecreationProductionDeviceTest {
    private data class DomQueueItem(val text: String, val percent: Int?)
    private data class DomQueueState(val found: Boolean, val items: List<DomQueueItem>)

    @Test
    fun homeContinuationAdvancesNotificationAndCompletesAfterReturning() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val homeUrl = DeviceTestHelpers.decodeUrl("homeUrlB64")
        val (activity, view) = DeviceTestHelpers.openMainWebView(instrumentation)
        var itemId: String? = null
        try {
            val beforeMaxHistory = DeviceTestHelpers.maxHistoryId(DeviceTestHelpers.history(instrumentation, view))
            val id = DeviceTestHelpers.enqueue(
                instrumentation,
                view,
                homeUrl,
                "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                isPlaylist = false,
            )
            itemId = id

            val activeDeadline = SystemClock.elapsedRealtime() + 90_000
            var startSql: DeviceTestHelpers.SqliteQueueSnapshot? = null
            var startNotifPercent = -1
            while (SystemClock.elapsedRealtime() < activeDeadline) {
                val sql = DeviceTestHelpers.readSqliteQueueSnapshot(context, id)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val part = DeviceTestHelpers.findPartFile(context.cacheDir, id)
                if (sql?.status == "downloading" && notice != null && part != null && part.length() >= 4096) {
                    val notification = notice.notification
                    val indeterminate = notification.extras.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, true)
                    val progress = notification.extras.getInt(Notification.EXTRA_PROGRESS, -1)
                    if (!indeterminate && progress >= 0) {
                        assertTrue(
                            "Progress notification must be ongoing",
                            (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0,
                        )
                        assertTrue(
                            "Progress notification must have no action buttons",
                            notification.actions == null || notification.actions.isEmpty(),
                        )
                        startSql = sql
                        startNotifPercent = progress
                        break
                    }
                }
                Thread.sleep(200)
            }
            assertTrue("Download and determinate notification did not become active before Home", startSql != null)
            val initialSql = startSql!!
            Log.i(TAG, "HOME_PRESSED item=$id sqlPercent=${initialSql.percent} notifPercent=$startNotifPercent")

            instrumentation.uiAutomation.executeShellCommand("input keyevent 3").close()
            val homeDeadline = SystemClock.elapsedRealtime() + 10_000
            var background = false
            while (SystemClock.elapsedRealtime() < homeDeadline) {
                instrumentation.runOnMainSync { background = !activity.hasWindowFocus() }
                if (background) break
                Thread.sleep(100)
            }
            assertTrue("Home did not move MainActivity out of focus", background)

            val windowStart = SystemClock.elapsedRealtime()
            var previousSqlPercent = initialSql.percent
            var previousNotifPercent = startNotifPercent
            var sqlChanges = 0
            var notifChanges = 0
            var samples = 0

            while (SystemClock.elapsedRealtime() - windowStart < 180_000) {
                var focused = true
                instrumentation.runOnMainSync { focused = activity.hasWindowFocus() }
                assertFalse("Activity returned to foreground unexpectedly during Home window", focused)

                val sql = DeviceTestHelpers.readSqliteQueueSnapshot(context, id)
                    ?: throw AssertionError("Queue row $id vanished during Home continuation")
                assertEquals("Queue item stopped advancing while on Home", "downloading", sql.status)
                assertTrue(
                    "SQLite progress regressed on Home: ${sql.percent} < $previousSqlPercent",
                    sql.percent >= previousSqlPercent,
                )
                if (sql.percent > previousSqlPercent) sqlChanges++
                previousSqlPercent = sql.percent

                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                    ?: throw AssertionError("Foreground notification vanished while on Home")
                val notification = notice.notification
                assertTrue(
                    "Progress notification lost ongoing flag on Home",
                    (notification.flags and Notification.FLAG_ONGOING_EVENT) != 0,
                )
                assertTrue(
                    "Progress notification unexpectedly exposed actions",
                    notification.actions == null || notification.actions.isEmpty(),
                )
                val notifPercent = notification.extras.getInt(Notification.EXTRA_PROGRESS, -1)
                val notifText = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
                assertTrue("Notification progress regressed on Home: $notifPercent < $previousNotifPercent", notifPercent >= previousNotifPercent)
                if (notifPercent > previousNotifPercent) notifChanges++
                previousNotifPercent = notifPercent

                samples++
                Log.i(
                    TAG,
                    "HOME_SAMPLE sample=$samples sqlPercent=$previousSqlPercent notifPercent=$previousNotifPercent notifText=$notifText",
                )
                Thread.sleep(15_000)
            }

            assertTrue("SQLite progress did not advance meaningfully on Home ($sqlChanges changes)", sqlChanges >= 3 && previousSqlPercent > initialSql.percent)
            assertTrue("Notification progress did not advance meaningfully on Home ($notifChanges changes)", notifChanges >= 3 && previousNotifPercent > startNotifPercent)
            Log.i(
                TAG,
                "HOME_WINDOW_OK samples=$samples sqlStart=${initialSql.percent} sqlEnd=$previousSqlPercent notifStart=$startNotifPercent notifEnd=$previousNotifPercent",
            )

            // Return to foreground and verify clean completion to History & MediaStore Downloads.
            instrumentation.uiAutomation.executeShellCommand("input keyevent 224").close()
            context.startActivity(
                Intent(context, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
            )
            val resumeFocusDeadline = SystemClock.elapsedRealtime() + 15_000
            var returnedToForeground = false
            while (SystemClock.elapsedRealtime() < resumeFocusDeadline) {
                instrumentation.runOnMainSync { returnedToForeground = activity.hasWindowFocus() }
                if (returnedToForeground) break
                Thread.sleep(150)
            }
            assertTrue("MainActivity did not return to foreground after Home", returnedToForeground)

            val doneDeadline = SystemClock.elapsedRealtime() + 120_000
            var completed = false
            while (SystemClock.elapsedRealtime() < doneDeadline) {
                val history = DeviceTestHelpers.history(instrumentation, view)
                val queue = DeviceTestHelpers.queue(instrumentation, view)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val downloads = DeviceTestHelpers.findDownloadsByTitlePrefix(context, "home-long")
                if (history.any {
                        it.optLong("id", 0L) > beforeMaxHistory &&
                            it.optJSONObject("request")?.optString("url") == homeUrl
                    } && queue.isEmpty() && notice == null && downloads.isNotEmpty()
                ) {
                    completed = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Home continuation download did not finish cleanly after returning", completed)
            itemId = null
        } finally {
            itemId?.let { id ->
                try {
                    DeviceTestHelpers.invoke(instrumentation, view, "remove_download", JSONObject().put("id", id))
                } catch (_: Throwable) {
                }
            }
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "home-long")
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test
    fun recreatedActivityRestoresQueueAndReceivesLiveEventsWithoutDuplicates() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val recreateUrl = DeviceTestHelpers.decodeUrl("recreateUrlB64")
        val queuedUrl = DeviceTestHelpers.decodeUrl("queuedUrlB64")
        val (firstActivity, firstView) = DeviceTestHelpers.openMainWebView(instrumentation)
        var activeActivity: MainActivity = firstActivity
        var activeView: WebView = firstView
        var activeId: String? = null
        var queuedId: String? = null
        val recreated = AtomicReference<MainActivity?>()
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) {
                if (activity is MainActivity && activity !== firstActivity) {
                    recreated.set(activity)
                }
            }
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        }
        firstActivity.application.registerActivityLifecycleCallbacks(callbacks)

        try {
            val processId = Process.myPid()
            val beforeMaxHistory = DeviceTestHelpers.maxHistoryId(DeviceTestHelpers.history(instrumentation, firstView))
            activeId = DeviceTestHelpers.enqueue(
                instrumentation,
                firstView,
                recreateUrl,
                "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                isPlaylist = false,
            )
            queuedId = DeviceTestHelpers.enqueue(
                instrumentation,
                firstView,
                queuedUrl,
                "mp3",
                JSONObject().put("type", "audio").put("bitrate", 128),
                isPlaylist = false,
            )

            val readyDeadline = SystemClock.elapsedRealtime() + 90_000
            var beforePercent = -1
            while (SystemClock.elapsedRealtime() < readyDeadline) {
                val dom = readQueueCardDom(instrumentation, firstView)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val firstItem = dom.items.firstOrNull { it.text.contains(recreateUrl) }
                val secondItem = dom.items.firstOrNull { it.text.contains(queuedUrl) }
                if (dom.found &&
                    dom.items.size == 2 &&
                    firstItem != null &&
                    secondItem != null &&
                    firstItem.text.contains("Downloading") &&
                    secondItem.text.contains("Queued") &&
                    (firstItem.percent ?: -1) > 0 &&
                    notice != null &&
                    AndroidEnginePlugin.hasActiveOperations()
                ) {
                    beforePercent = firstItem.percent!!
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Initial 2-item queue never rendered active progress before recreation", beforePercent > 0)
            Log.i(TAG, "BEFORE_RECREATE pid=$processId domCount=2 domPercent=$beforePercent activeOps=${AndroidEnginePlugin.hasActiveOperations()}")

            instrumentation.runOnMainSync { firstActivity.recreate() }
            val recreateDeadline = SystemClock.elapsedRealtime() + 30_000
            while (recreated.get() == null && SystemClock.elapsedRealtime() < recreateDeadline) {
                Thread.sleep(100)
            }
            val secondActivity = recreated.get()
                ?: throw AssertionError("Android did not create a new MainActivity on recreate()")
            val secondView = DeviceTestHelpers.awaitWebView(instrumentation, secondActivity)
            DeviceTestHelpers.awaitBridge(instrumentation, secondView)
            activeActivity = secondActivity
            activeView = secondView

            assertTrue("Recreated Activity did not replace WebView instance", secondView !== firstView)
            assertEquals("Process ID changed across Activity recreation", processId, Process.myPid())

            // Observe the new React DOM directly without calling get_queue from the test.
            val restoreDeadline = SystemClock.elapsedRealtime() + 25_000
            var restoredPercent = -1
            while (SystemClock.elapsedRealtime() < restoreDeadline) {
                val dom = readQueueCardDom(instrumentation, secondView)
                val firstItem = dom.items.firstOrNull { it.text.contains(recreateUrl) }
                val secondItem = dom.items.firstOrNull { it.text.contains(queuedUrl) }
                if (dom.found &&
                    dom.items.size == 2 &&
                    firstItem != null &&
                    secondItem != null &&
                    firstItem.text.contains("Downloading") &&
                    secondItem.text.contains("Queued") &&
                    (firstItem.percent ?: -1) >= beforePercent
                ) {
                    restoredPercent = firstItem.percent!!
                    break
                }
                Thread.sleep(100)
            }
            assertTrue("Recreated WebView did not restore 2-item queue via get_queue", restoredPercent >= beforePercent)
            assertTrue("Foreground notification vanished during Activity recreation", DeviceTestHelpers.activeDownloadNotification(context) != null)
            assertTrue("Engine operation stopped during Activity recreation", AndroidEnginePlugin.hasActiveOperations())
            Log.i(TAG, "AFTER_RECREATE pid=$processId domCount=2 domPercent=$restoredPercent activeOps=true")

            // Verify live queue:item-updated events advance the recreated UI DOM without manual refresh.
            val liveDeadline = SystemClock.elapsedRealtime() + 45_000
            var livePercent = -1
            while (SystemClock.elapsedRealtime() < liveDeadline) {
                val dom = readQueueCardDom(instrumentation, secondView)
                val firstItem = dom.items.firstOrNull { it.text.contains(recreateUrl) }
                if (dom.found && dom.items.size == 2 && (firstItem?.percent ?: -1) > restoredPercent) {
                    livePercent = firstItem!!.percent!!
                    break
                }
                Thread.sleep(200)
            }
            assertTrue("Recreated WebView did not receive live progress events", livePercent > restoredPercent)
            Log.i(TAG, "LIVE_EVENT_AFTER_RECREATE domCount=2 domPercent=$livePercent")

            // Remove the waiting second item and let the active item finish normally.
            DeviceTestHelpers.invoke(instrumentation, secondView, "remove_download", JSONObject().put("id", queuedId!!))
            queuedId = null

            val doneDeadline = SystemClock.elapsedRealtime() + 140_000
            var completed = false
            var lastDiag = "none"
            while (SystemClock.elapsedRealtime() < doneDeadline) {
                val history = DeviceTestHelpers.history(instrumentation, secondView)
                val queue = DeviceTestHelpers.queue(instrumentation, secondView)
                val notice = DeviceTestHelpers.activeDownloadNotification(context)
                val dom = readQueueCardDom(instrumentation, secondView)
                val downloads = DeviceTestHelpers.findDownloadsByTitlePrefix(context, "recreate-long")
                val hasHistory = history.any {
                    it.optLong("id", 0L) > beforeMaxHistory &&
                        it.optJSONObject("request")?.optString("url") == recreateUrl
                }
                lastDiag = "hasHistory=$hasHistory historySize=${history.size} queueSize=${queue.size} notice=${notice != null} domFound=${dom.found} domItems=${dom.items.size} downloads=${downloads.size}"
                if (hasHistory && queue.isEmpty() && notice == null && dom.found && dom.items.isEmpty() && downloads.isNotEmpty()) {
                    completed = true
                    break
                }
                Thread.sleep(250)
            }
            assertTrue("Active download did not complete cleanly after Activity recreation ($lastDiag)", completed)
            activeId = null
        } finally {
            firstActivity.application.unregisterActivityLifecycleCallbacks(callbacks)
            queuedId?.let { id ->
                try {
                    DeviceTestHelpers.invoke(instrumentation, activeView, "remove_download", JSONObject().put("id", id))
                } catch (_: Throwable) {
                }
            }
            activeId?.let { id ->
                try {
                    DeviceTestHelpers.invoke(instrumentation, activeView, "remove_download", JSONObject().put("id", id))
                } catch (_: Throwable) {
                }
            }
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "recreate-long")
            DeviceTestHelpers.deleteDownloadsByPrefix(context, "track-1")
            instrumentation.runOnMainSync {
                activeActivity.finish()
                if (activeActivity !== firstActivity && !firstActivity.isFinishing) {
                    firstActivity.finish()
                }
            }
        }
    }

    private fun readQueueCardDom(
        instrumentation: android.app.Instrumentation,
        view: WebView,
    ): DomQueueState {
        val raw = DeviceTestHelpers.evaluate(
            instrumentation,
            view,
            """
            (() => {
              const section = [...document.querySelectorAll('section')].find(s => {
                const title = s.querySelector('h2,h3')?.textContent?.trim();
                return title === 'Queue' || title === 'Cola';
              });
              if (!section) return JSON.stringify({found: false, items: []});
              const items = [...section.querySelectorAll('ul > li')].map(li => {
                const bar = li.querySelector('[role="progressbar"]');
                const aria = bar ? Number(bar.getAttribute('aria-valuenow')) : null;
                return {
                  text: (li.innerText || li.textContent || '').trim(),
                  percent: Number.isFinite(aria) ? aria : null,
                };
              });
              return JSON.stringify({found: true, items});
            })()
            """.trimIndent(),
        )
        if (raw.isBlank()) return DomQueueState(found = false, items = emptyList())
        val parsed = JSONObject(raw)
        val array = parsed.optJSONArray("items")
        val items = buildList {
            if (array != null) {
                for (index in 0 until array.length()) {
                    val obj = array.optJSONObject(index) ?: continue
                    val percent = if (obj.isNull("percent")) null else obj.optInt("percent")
                    add(DomQueueItem(obj.optString("text"), percent))
                }
            }
        }
        return DomQueueState(found = parsed.optBoolean("found", false), items = items)
    }

    companion object {
        private const val TAG = "Zownload5B06"
    }
}
