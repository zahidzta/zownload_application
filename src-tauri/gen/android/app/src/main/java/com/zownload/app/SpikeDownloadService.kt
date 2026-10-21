// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 zahidzta

package com.zownload.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// This service only keeps the Rust-owned job in the foreground. It has no queue.
class SpikeDownloadService : Service() {
    companion object {
        private const val TAG = "Zownload0C08"
        private const val CHANNEL = "spike-download"
        private const val NOTICE_ID = 108

        class StartAck {
            val latch = CountDownLatch(1)
            @Volatile var error: String? = null
            fun await(): String? = if (latch.await(10, TimeUnit.SECONDS)) error else "Service did not start in time"
        }

        @Volatile private var pendingStart: StartAck? = null

        fun start(context: Context): StartAck {
            val ack = StartAck()
            pendingStart = ack
            try {
                val intent = Intent(context, SpikeDownloadService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
            } catch (error: Exception) {
                ack.error = error.message ?: error.javaClass.simpleName
                ack.latch.countDown()
            }
            return ack
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SpikeDownloadService::class.java))
        }
    }

    private var timedOut = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW)
                )
            }
            manager.cancel(NOTICE_ID)
            val notification = notice("Downloading audio", true)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTICE_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTICE_ID, notification)
            }
            Log.i(TAG, "SERVICE_STARTED type=dataSync startId=$startId")
        } catch (error: Exception) {
            Log.e(TAG, "SERVICE_START_FAILED", error)
            pendingStart?.error = error.message ?: error.javaClass.simpleName
            stopSelf()
        } finally {
            pendingStart?.latch?.countDown()
            pendingStart = null
        }
        return START_NOT_STICKY
    }

    // Android 15 gives us only seconds to stop after this callback. The plugin
    // resolves its waiting Rust call, which checkpoints the queue as paused.
    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.i(TAG, "SERVICE_TIMEOUT startId=$startId type=$fgsType")
        timedOut = true
        try {
            AndroidSpikePlugin.onForegroundTimeout()
            getSystemService(NotificationManager::class.java)
                .notify(NOTICE_ID, notice("Downloads paused. Open Zownload to continue.", false))
            stopForeground(STOP_FOREGROUND_DETACH)
        } finally {
            // Android gives only a few seconds before it crashes a timed-out
            // service. Stopping cannot depend on the Rust callback succeeding.
            stopSelf()
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "TASK_REMOVED")
        // Return the interruption to Rust while this foreground service keeps
        // the process alive. Rust saves paused, cancels the engine, then stops us.
        if (!AndroidSpikePlugin.onTaskRemoved()) {
            Log.w(TAG, "TASK_REMOVED_NO_ACTIVE_DOWNLOAD")
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (!timedOut) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            getSystemService(NotificationManager::class.java).cancel(NOTICE_ID)
        }
        Log.i(TAG, "SERVICE_STOPPED timedOut=$timedOut")
        super.onDestroy()
    }

    private fun notice(message: String, ongoing: Boolean): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Zownload")
            .setContentText(message)
            .setContentIntent(openApp)
            .setOngoing(ongoing)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .build()
    }
}
