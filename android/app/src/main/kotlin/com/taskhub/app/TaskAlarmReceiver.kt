package com.taskhub.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject

class TaskAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "TaskHub reminder"
        val body = intent.getStringExtra("body") ?: "Your task is scheduled now."
        showNotification(context, intent.getIntExtra("notificationId", 1), title, body)
    }

    companion object {
        private const val PREFS = "taskhub_alarms"
        private const val CHANNEL = "taskhub_alarm_channel_meow_v2"
        private const val TIMER_PREFS = "taskhub_running_timer"
        private const val TIMER_NOTIFICATION_ID = 4314
        private const val TIMER_CHANNEL = "taskhub_running_timer_v1"

        private fun notificationsEnabled(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) return false
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return Build.VERSION.SDK_INT < 24 || manager.areNotificationsEnabled()
        }

        fun showNotification(context: Context, notificationId: Int, title: String, body: String) {
        if (!notificationsEnabled(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "TaskHub alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Task start and deadline reminders with the TaskHub meow"
                    enableVibration(true)
                    setSound(android.net.Uri.parse("android.resource://${context.packageName}/${R.raw.meow}"), android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION).build())
                }
            )
        }
        val openApp = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = openApp?.let {
            PendingIntent.getActivity(context, 4313, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            android.app.Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(body))
            .setCategory(android.app.Notification.CATEGORY_ALARM)
            .setPriority(android.app.Notification.PRIORITY_MAX)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        manager.notify(notificationId, notification)
        }

        fun showRunningTimer(
            context: Context,
            title: String,
            startedAt: Long,
            body: String = "Task timer is running",
        ) {
            if (!notificationsEnabled(context)) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        TIMER_CHANNEL,
                        "Running task timer",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Shows the elapsed time for your active TaskHub task"
                        setSound(null, null)
                        enableVibration(false)
                    },
                )
            }
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = launch?.let {
                PendingIntent.getActivity(
                    context,
                    TIMER_NOTIFICATION_ID,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                android.app.Notification.Builder(context, TIMER_CHANNEL)
            } else {
                android.app.Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(title)
                .setContentText(body)
                .setWhen(startedAt)
                .setUsesChronometer(true)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(contentIntent)
                .build()
            manager.notify(TIMER_NOTIFICATION_ID, notification)
            context.getSharedPreferences(TIMER_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("title", title)
                .putString("body", body)
                .putLong("started_at", startedAt)
                .apply()
        }

        fun hideRunningTimer(context: Context) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(TIMER_NOTIFICATION_ID)
            context.getSharedPreferences(TIMER_PREFS, Context.MODE_PRIVATE)
                .edit().clear().apply()
        }

        fun restoreRunningTimer(context: Context) {
            val preferences = context.getSharedPreferences(TIMER_PREFS, Context.MODE_PRIVATE)
            val title = preferences.getString("title", null) ?: return
            val body = preferences.getString("body", "Task timer is running")
            val startedAt = preferences.getLong("started_at", 0L)
            if (startedAt > 0L) {
                showRunningTimer(context, title, startedAt, body ?: "Task timer is running")
            }
        }

        fun schedule(context: Context, id: String, at: Long, title: String, body: String, persist: Boolean = true) {
            if (at <= System.currentTimeMillis()) return
            if (persist) {
                val previous = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(id, null)
                if (previous != null) {
                    val sameAlarm = runCatching { JSONObject(previous).getLong("at") == at }.getOrDefault(false)
                    if (sameAlarm) return
                }
            }
            val intent = Intent(context, TaskAlarmReceiver::class.java)
                .setAction("taskhub.alarm.$id")
                .putExtra("title", title)
                .putExtra("body", body)
                .putExtra("notificationId", id.hashCode())
            val pending = PendingIntent.getBroadcast(
                context,
                id.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= 23) {
                try {
                    if (Build.VERSION.SDK_INT >= 31 && !alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                    } else {
                        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                    }
                } catch (_: SecurityException) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
                }
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, at, pending)
            }
            if (persist) {
                val data = JSONObject().put("at", at).put("title", title).put("body", body)
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(id, data.toString()).apply()
            }
        }

        fun cancelTask(context: Context, taskId: String) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val editor = preferences.edit()
            preferences.all.keys.filter { it.startsWith("$taskId:") }.forEach { id ->
                val intent = Intent(context, TaskAlarmReceiver::class.java).setAction("taskhub.alarm.$id")
                PendingIntent.getBroadcast(
                    context,
                    id.hashCode(),
                    intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                )?.let { (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(it) }
                editor.remove(id)
            }
            editor.apply()
        }

        fun cancelAlarm(context: Context, id: String) {
            val intent = Intent(context, TaskAlarmReceiver::class.java)
                .setAction("taskhub.alarm.$id")
            PendingIntent.getBroadcast(
                context,
                id.hashCode(),
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            )?.let { pending ->
                (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending)
                pending.cancel()
            }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().remove(id).apply()
        }
    }
}

class TaskBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        TaskAlarmReceiver.restoreRunningTimer(context)
        val saved = context.getSharedPreferences("taskhub_alarms", Context.MODE_PRIVATE).all
        saved.forEach { (id, raw) ->
            if (raw is String) {
                runCatching {
                    val item = JSONObject(raw)
                    val at = item.getLong("at")
                    if (at > System.currentTimeMillis()) {
                        TaskAlarmReceiver.schedule(context, id, at, item.getString("title"), item.getString("body"), false)
                    }
                }
            }
        }
    }
}
