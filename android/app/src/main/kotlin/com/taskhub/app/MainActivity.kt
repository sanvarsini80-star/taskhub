package com.taskhub.app

import android.Manifest
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionRequested = false
    private var notificationPermissionPending = false
    private var pendingTimerTitle: String? = null
    private var pendingTimerBody: String? = null
    private var pendingTimerStartedAt: Long? = null
    private val pendingTaskNotifications = mutableListOf<Triple<Int, String, String>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskhub/alarms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleTaskAlarms" -> {
                        val alarms = call.argument<List<Map<String, Any>>>("alarms") ?: emptyList()
                        requestNotificationPermissionIfNeeded()
                        alarms.forEach { alarm ->
                            val id = alarm["id"] as? String ?: return@forEach
                            val at = (alarm["at"] as? Number)?.toLong() ?: return@forEach
                            val title = alarm["title"] as? String ?: "TaskHub reminder"
                            val body = alarm["body"] as? String ?: "Your task is scheduled now."
                            TaskAlarmReceiver.schedule(this, id, at, title, body)
                        }
                        result.success(null)
                    }
                    "cancelTaskAlarms" -> {
                        val taskId = call.argument<String>("taskId")
                        if (taskId != null) TaskAlarmReceiver.cancelTask(this, taskId)
                        result.success(null)
                    }
                    "cancelTaskAlarm" -> {
                        val alarmId = call.argument<String>("alarmId")
                        if (alarmId != null) TaskAlarmReceiver.cancelAlarm(this, alarmId)
                        result.success(null)
                    }
                    "showRunningTimer" -> {
                        val title = call.argument<String>("title") ?: "TaskHub timer"
                        val body = call.argument<String>("body") ?: "Task timer is running"
                        val startedAt = call.argument<Number>("startedAt")?.toLong() ?: System.currentTimeMillis()
                        showRunningTimer(title, startedAt, body)
                        result.success(null)
                    }
                    "hideRunningTimer" -> {
                        TaskAlarmReceiver.hideRunningTimer(this)
                        result.success(null)
                    }
                    "showTaskNotification" -> {
                        val title = call.argument<String>("title") ?: "TaskHub reminder"
                        val body = call.argument<String>("body") ?: "You have a task update."
                        val notificationId = call.argument<Number>("notificationId")?.toInt() ?: title.hashCode()
                        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        if (!requestNotificationPermissionIfNeeded()) {
                            if (notificationPermissionPending) {
                                pendingTaskNotifications.add(Triple(notificationId, title, body))
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) {
                            result.success(false)
                        } else {
                            TaskAlarmReceiver.showNotification(this, notificationId, title, body)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 4312) return
        notificationPermissionPending = false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            pendingTaskNotifications.forEach { (id, title, body) ->
                TaskAlarmReceiver.showNotification(this, id, title, body)
            }
            pendingTaskNotifications.clear()
            val title = pendingTimerTitle
            val body = pendingTimerBody
            val startedAt = pendingTimerStartedAt
            if (title != null && body != null && startedAt != null) {
                showRunningTimer(title, startedAt, body)
            }
        } else {
            pendingTaskNotifications.clear()
        }
        pendingTimerTitle = null
        pendingTimerBody = null
        pendingTimerStartedAt = null
    }

    private fun showRunningTimer(title: String, startedAt: Long, body: String) {
        if (!requestNotificationPermissionIfNeeded()) {
            pendingTimerTitle = title
            pendingTimerBody = body
            pendingTimerStartedAt = startedAt
            return
        }
        TaskAlarmReceiver.showRunningTimer(this, title, startedAt, body)
    }

    private fun requestNotificationPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) return true
        if (!notificationPermissionRequested) {
            notificationPermissionRequested = true
            notificationPermissionPending = true
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4312)
        }
        return false
    }
}
