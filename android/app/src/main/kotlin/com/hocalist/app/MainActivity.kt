package com.hocalist.app

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "hocalist_updates", "Hocalist updates", NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.description = "Offers, messages and meeting updates"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
