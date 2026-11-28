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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

internal data class NotificationContent(
    val title: String,
    val text: String,
    val percent: Int,
    val indeterminate: Boolean,
    val ongoing: Boolean,
)

internal fun formatNotificationContent(
    title: String,
    detail: String,
    percent: Int,
    indeterminate: Boolean,
    ongoing: Boolean,
): NotificationContent {
    val safeTitle = title.ifBlank { "Zownload" }
    val safeDetail = detail.ifBlank { "Downloading" }
    val clamped = percent.coerceIn(0, 100)
    return NotificationContent(
        title = safeTitle,
        text = safeDetail,
        percent = clamped,
        indeterminate = indeterminate,
        ongoing = ongoing,
    )
}

internal fun shouldPostNotificationUpdate(
    previous: NotificationContent?,
    next: NotificationContent,
): Boolean = previous != next

// Stateless Android foreground service for active Rust-owned queue work.
// Holds no queue items, retry state, or business rules.
class DownloadForegroundService : Service() {
    companion object {
        private const val TAG = "ZownloadFgs"
        internal const val CHANNEL_ID = "zownload-downloads"
        internal const val NOTIFICATION_ID = 1001
        internal const val DEFAULT_TIMEOUT_DETAIL = "Downloads paused. Open Zownload to continue."

        private const val ACTION_START = "com.zownload.app.action.START_FGS"
        private const val ACTION_UPDATE = "com.zownload.app.action.UPDATE_FGS"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_DETAIL = "detail"
        private const val EXTRA_PERCENT = "percent"
        private const val EXTRA_INDETERMINATE = "indeterminate"
        private const val EXTRA_TIMEOUT_DETAIL = "timeoutDetail"

        class StartAck {
            val latch = CountDownLatch(1)
            @Volatile var error: String? = null
            fun await(): String? =
                if (latch.await(10, TimeUnit.SECONDS)) error else "Foreground service did not start in time"
        }

        @Volatile private var pendingStart: StartAck? = null
        @Volatile internal var activeInstance: DownloadForegroundService? = null

        fun start(
            context: Context,
            title: String,
            detail: String,
            percent: Int,
            indeterminate: Boolean,
            timeoutDetail: String,
        ): StartAck {
            val ack = StartAck()
            pendingStart = ack
            try {
                val intent = Intent(context, DownloadForegroundService::class.java).apply {
                    action = ACTION_START
                    putExtra(EXTRA_TITLE, title)
                    putExtra(EXTRA_DETAIL, detail)
                    putExtra(EXTRA_PERCENT, percent)
                    putExtra(EXTRA_INDETERMINATE, indeterminate)
                    putExtra(EXTRA_TIMEOUT_DETAIL, timeoutDetail)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                ack.error = error.message ?: error.javaClass.simpleName
                ack.latch.countDown()
                pendingStart = null
            }
            return ack
        }

        fun updateProgress(
            context: Context,
            title: String,
            detail: String,
            percent: Int,
            indeterminate: Boolean,
        ) {
            val service = activeInstance ?: return
            service.postProgress(title, detail, percent, indeterminate)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadForegroundService::class.java))
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var timedOut = false
    @Volatile private var timeoutDetail = DEFAULT_TIMEOUT_DETAIL
    @Volatile private var lastPostedContent: NotificationContent? = null
    private var stopFallback: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val detail = intent?.getStringExtra(EXTRA_DETAIL).orEmpty()
        val percent = intent?.getIntExtra(EXTRA_PERCENT, 0) ?: 0
        val indeterminate = intent?.getBooleanExtra(EXTRA_INDETERMINATE, true) ?: true
        val customTimeout = intent?.getStringExtra(EXTRA_TIMEOUT_DETAIL).orEmpty()
        if (customTimeout.isNotBlank()) {
            timeoutDetail = customTimeout
        }

        if (action == ACTION_UPDATE) {
            if (!timedOut) {
                postProgress(title, detail, percent, indeterminate)
            }
            return START_NOT_STICKY
        }

        timedOut = false
        try {
            ensureChannel()
            val manager = getSystemService(NotificationManager::class.java)
            manager.cancel(NOTIFICATION_ID)
            val content = formatNotificationContent(title, detail, percent, indeterminate, ongoing = true)
            val notification = buildNotification(content)
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
            lastPostedContent = content
            activeInstance = this
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

    internal fun postProgress(
        title: String,
        detail: String,
        percent: Int,
        indeterminate: Boolean,
    ) {
        if (timedOut) return
        ensureChannel()
        val content = formatNotificationContent(title, detail, percent, indeterminate, ongoing = true)
        if (!shouldPostNotificationUpdate(lastPostedContent, content)) return
        lastPostedContent = content
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(content))
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "TASK_REMOVED")
        if (!AndroidEnginePlugin.onTaskRemoved()) {
            Log.w(TAG, "TASK_REMOVED_NO_ACTIVE_LISTENER")
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
            stopSelf()
        } else {
            val fallback = Runnable {
                Log.w(TAG, "TASK_REMOVED_STOP_FALLBACK")
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
                stopSelf()
            }
            stopFallback = fallback
            mainHandler.postDelayed(fallback, 2_500)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        handleForegroundTimeout(startId, fgsType)
    }

    internal fun handleForegroundTimeout(startId: Int, fgsType: Int) {
        Log.i(TAG, "SERVICE_TIMEOUT startId=$startId type=$fgsType")
        timedOut = true
        lastPostedContent = null
        try {
            AndroidEnginePlugin.onForegroundTimeout()
            ensureChannel()
            val content = formatNotificationContent(
                title = "Zownload",
                detail = timeoutDetail,
                percent = 0,
                indeterminate = false,
                ongoing = false,
            )
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification(content))
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        } finally {
            stopSelf(startId)
        }
    }

    override fun onDestroy() {
        stopFallback?.let { mainHandler.removeCallbacks(it) }
        stopFallback = null
        lastPostedContent = null
        if (activeInstance === this) {
            activeInstance = null
        }
        if (!timedOut) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        }
        Log.i(TAG, "SERVICE_STOPPED timedOut=$timedOut")
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    private fun buildNotification(content: NotificationContent): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setContentIntent(openApp)
            .setOngoing(content.ongoing)
            .setAutoCancel(!content.ongoing)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (content.ongoing) {
            builder.setProgress(100, content.percent, content.indeterminate)
        } else {
            builder.setProgress(0, 0, false)
        }
        return builder.build()
    }
}
