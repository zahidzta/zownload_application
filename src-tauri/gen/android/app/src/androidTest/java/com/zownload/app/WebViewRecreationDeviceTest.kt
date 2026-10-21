// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import org.json.JSONTokener
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WebViewRecreationDeviceTest {
    private data class Display(val id: String, val state: String, val percent: Double)

    @Test
    fun recreatedActivityRestoresQueueAndReceivesProgressEvents() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val encoded = InstrumentationRegistry.getArguments().getString("youtubeUrlB64")
        assertTrue("Pass the approved long YouTube URL", !encoded.isNullOrBlank())
        val url = String(Base64.decode(encoded, Base64.DEFAULT), Charsets.UTF_8)
        val context = instrumentation.targetContext
        AndroidSpikePlugin.testRateLimit = "32K"
        val firstActivity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        val firstView = awaitView(instrumentation, firstActivity)
        val processId = Process.myPid()
        val recreated = AtomicReference<MainActivity?>()
        val callbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, state: Bundle?) {
                if (activity is MainActivity && activity !== firstActivity) recreated.set(activity)
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
            evaluate(instrumentation, firstView, """
                window.__zownloadRecreateResult = '';
                window.__TAURI_INTERNALS__.invoke('enqueue_download', {
                  request: {url: ${JSONObject.quote(url)}, format: 'mp3',
                    quality: {type: 'audio', bitrate: 128}, isPlaylist: false}
                }).then(id => window.__zownloadRecreateResult = 'OK:' + id,
                        error => window.__zownloadRecreateResult = 'ERR:' + String(error));
            """.trimIndent())
            val deadline = SystemClock.elapsedRealtime() + 120_000
            var before: Display? = null
            var children = emptySet<String>()
            while (SystemClock.elapsedRealtime() < deadline) {
                val shown = display(instrumentation, firstView)
                val pids = childPids(instrumentation, processId)
                if (shown?.state == "downloading" && pids.isNotEmpty()) {
                    before = shown
                    children = pids
                    break
                }
                val result = evaluate(instrumentation, firstView, "window.__zownloadRecreateResult || ''")
                assertTrue("Download failed before recreation: $result", !result.startsWith("ERR:"))
                Thread.sleep(500)
            }
            assertTrue("UI did not show the active job and engine", before != null)
            val first = before!!
            Log.i("Zownload0C12", "BEFORE pid=$processId item=${first.id} status=${first.state} percent=${first.percent} children=${children.sorted().joinToString(",")}")

            instrumentation.runOnMainSync { firstActivity.recreate() }
            val recreateDeadline = SystemClock.elapsedRealtime() + 30_000
            while (recreated.get() == null && SystemClock.elapsedRealtime() < recreateDeadline) Thread.sleep(100)
            val secondActivity = recreated.get()
            assertTrue("Android did not create a new Activity", secondActivity != null)
            val secondView = awaitView(instrumentation, secondActivity!!)
            assertTrue("Activity kept the original WebView", secondView !== firstView)
            assertTrue("App process changed during Activity recreation", Process.myPid() == processId)

            var restored: Display? = null
            val uiDeadline = SystemClock.elapsedRealtime() + 20_000
            while (SystemClock.elapsedRealtime() < uiDeadline) {
                val shown = display(instrumentation, secondView)
                if (shown?.id == first.id && shown.state == "downloading") {
                    restored = shown
                    break
                }
                Thread.sleep(100)
            }
            assertTrue("New UI did not restore the active Rust queue item", restored != null)
            val second = restored!!
            assertTrue("Restored UI progress went backwards", second.percent >= first.percent)
            assertTrue("Engine child changed during Activity recreation",
                childPids(instrumentation, processId) == children)
            Log.i("Zownload0C12", "RECREATED pid=$processId item=${second.id} status=${second.state} percent=${second.percent} children=${children.sorted().joinToString(",")}")

            // No explicit refresh or get_queue is called by the test after
            // recreation. A later DOM change must come from the new UI's
            // queue event listener asking Rust for its latest snapshot.
            val eventDeadline = SystemClock.elapsedRealtime() + 90_000
            var live: Display? = null
            while (SystemClock.elapsedRealtime() < eventDeadline) {
                val shown = display(instrumentation, secondView)
                if (shown?.id == first.id && shown.state == "downloading" &&
                    shown.percent > second.percent) {
                    live = shown
                    break
                }
                Thread.sleep(500)
            }
            assertTrue("Recreated UI did not receive a later progress event", live != null)
            assertTrue("Engine child changed or duplicated after new UI subscribed",
                childPids(instrumentation, processId) == children)
            Log.i("Zownload0C12", "LIVE_EVENT item=${live!!.id} status=${live.state} percent=${live.percent} children=${children.sorted().joinToString(",")}")
        } finally {
            firstActivity.application.unregisterActivityLifecycleCallbacks(callbacks)
            AndroidSpikePlugin.testRateLimit = null
        }
    }

    private fun display(instrumentation: android.app.Instrumentation, view: WebView): Display? {
        val json = evaluate(instrumentation, view, """
            (() => {
              const rows = [...document.querySelectorAll('dt')];
              const value = label => rows.find(row => row.textContent === label)?.nextElementSibling?.textContent?.trim() || '';
              return JSON.stringify({id: value('Item ID'), state: value('Item state'), progress: value('Progress')});
            })()
        """.trimIndent())
        if (json.isEmpty()) return null
        val values = JSONObject(json)
        val percent = values.getString("progress").removeSuffix("%").toDoubleOrNull() ?: return null
        return Display(values.getString("id"), values.getString("state"), percent)
    }

    private fun childPids(instrumentation: android.app.Instrumentation, parent: Int): Set<String> {
        val descriptor = instrumentation.uiAutomation.executeShellCommand("ps -A -o PID,PPID,NAME")
        val output = descriptor.use { java.io.FileInputStream(it.fileDescriptor).bufferedReader().readText() }
        return output.lineSequence().mapNotNull { line ->
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size >= 3 && fields[1] == parent.toString()) fields[0] else null
        }.toSet()
    }

    private fun awaitView(instrumentation: android.app.Instrumentation, activity: Activity): WebView {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        var view: WebView? = null
        while (view == null && SystemClock.elapsedRealtime() < deadline) {
            instrumentation.runOnMainSync { view = findView(activity.window.decorView) }
            if (view == null) Thread.sleep(100)
        }
        assertTrue("Tauri WebView missing", view != null)
        while (SystemClock.elapsedRealtime() < deadline &&
            evaluate(instrumentation, view!!, "typeof window.__TAURI_INTERNALS__?.invoke") != "function"
        ) Thread.sleep(100)
        assertTrue("Tauri bridge missing",
            evaluate(instrumentation, view!!, "typeof window.__TAURI_INTERNALS__?.invoke") == "function")
        return view!!
    }

    private fun findView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            findView(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun evaluate(instrumentation: android.app.Instrumentation, view: WebView, script: String): String {
        val latch = CountDownLatch(1)
        val answer = AtomicReference("")
        instrumentation.runOnMainSync {
            view.evaluateJavascript(script) { value ->
                answer.set((JSONTokener(value).nextValue() as? String).orEmpty())
                latch.countDown()
            }
        }
        assertTrue("WebView callback timed out", latch.await(10, TimeUnit.SECONDS))
        return answer.get()
    }
}
