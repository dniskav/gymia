package com.gymia.app

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock

object RestNotifications {
    private const val channelId = "gymia_rest"
    private const val requestId = 8401
    private const val testRequestId = 8403
    fun preferences(context: Context) = context.getSharedPreferences("gymia_rest", Context.MODE_PRIVATE)
    fun permitted(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            (Build.VERSION.SDK_INT < 24 || manager.areNotificationsEnabled())
    }
    fun exact(context: Context): Boolean = Build.VERSION.SDK_INT < 31 ||
        context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    private fun pending(context: Context, id: String = "", end: Long = 0, name: String = ""): PendingIntent =
        PendingIntent.getBroadcast(context, requestId,
            Intent(context, RestAlarmReceiver::class.java).putExtra("id", id).putExtra("end", end).putExtra("name", name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(pending(context))
        preferences(context).edit().remove("id").remove("end").apply()
        context.getSystemService(NotificationManager::class.java).cancel(requestId)
    }
    fun schedule(context: Context, id: String, end: Long, name: String) {
        cancel(context)
        if (!preferences(context).getBoolean("enabled", false) || !permitted(context) || end <= System.currentTimeMillis()) return
        preferences(context).edit().putString("id", id).putLong("end", end).apply()
        val alarm = context.getSystemService(AlarmManager::class.java)
        val trigger = SystemClock.elapsedRealtime() + (end - System.currentTimeMillis())
        val intent = pending(context, id, end, name)
        if (exact(context)) alarm.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, intent)
        else alarm.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, trigger, intent)
    }
    fun notify(context: Context, name: String): Boolean {
        if (!permitted(context)) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, "Descanso de entrenamiento", NotificationManager.IMPORTANCE_HIGH).apply {
                enableVibration(true)
                description = "Avisa cuando termina el descanso que configuraste."
            })
            if (manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val open = PendingIntent.getActivity(context, requestId, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context)
        manager.notify(requestId, builder.setSmallIcon(R.drawable.ic_trackia)
            .setContentTitle("Descanso terminado")
            .setContentText("$name · puedes comenzar cuando quieras")
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setDefaults(Notification.DEFAULT_ALL).build())
        return true
    }
    fun notifyTest(context: Context): Boolean {
        if (!preferences(context).getBoolean("enabled", false) || !permitted(context)) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, "Descanso de entrenamiento", NotificationManager.IMPORTANCE_HIGH).apply {
                enableVibration(true)
                description = "Avisa cuando termina el descanso que configuraste."
            })
            if (manager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val open = PendingIntent.getActivity(context, testRequestId, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context)
        manager.notify(testRequestId, builder.setSmallIcon(R.drawable.ic_trackia)
            .setContentTitle("Prueba de notificaciones")
            .setContentText("TrackIA puede avisarte en este móvil.")
            .setContentIntent(open).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setDefaults(Notification.DEFAULT_ALL).build())
        return true
    }
}

class RestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val preferences = RestNotifications.preferences(context)
        val id = intent.getStringExtra("id") ?: return
        val end = intent.getLongExtra("end", 0)
        if (!preferences.getBoolean("enabled", false) || preferences.getString("id", null) != id || preferences.getLong("end", 0) != end) return
        if (System.currentTimeMillis() < end) return
        preferences.edit().remove("id").remove("end").apply()
        if (RestNotifications.notify(context, intent.getStringExtra("name") ?: "Entrenamiento")) {
            preferences.edit().putString("lastDeliveredId", id).putLong("lastDeliveredEnd", end).apply()
        }
    }
}
