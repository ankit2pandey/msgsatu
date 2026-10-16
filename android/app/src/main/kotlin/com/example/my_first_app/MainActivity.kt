package com.parasariz.sms_free

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "tachneat_sms_service",
                "Tachneat SMS Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Tachneat connected to receive SMS jobs."
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
