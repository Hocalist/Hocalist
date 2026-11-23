package com.hocalist.app

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import com.google.firebase.analytics.FirebaseAnalytics
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences("hocalist_analytics", MODE_PRIVATE)
        val analytics = FirebaseAnalytics.getInstance(this)
        fun applyConsent(enabled: Boolean) {
            analytics.setConsent(mapOf(
                FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE to
                    if (enabled) FirebaseAnalytics.ConsentStatus.GRANTED else FirebaseAnalytics.ConsentStatus.DENIED,
                FirebaseAnalytics.ConsentType.AD_STORAGE to FirebaseAnalytics.ConsentStatus.DENIED,
                FirebaseAnalytics.ConsentType.AD_USER_DATA to FirebaseAnalytics.ConsentStatus.DENIED,
                FirebaseAnalytics.ConsentType.AD_PERSONALIZATION to FirebaseAnalytics.ConsentStatus.DENIED
            ))
            analytics.setAnalyticsCollectionEnabled(enabled)
        }
        applyConsent(preferences.getBoolean("enabled", false))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hocalist/marketplace_analytics")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getConsent" -> result.success(preferences.getBoolean("enabled", false))
                    "setConsent" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("invalid_consent", "A consent choice is required.", null)
                        } else {
                            val saved = preferences.edit().putBoolean("enabled", enabled).commit()
                            if (saved) applyConsent(enabled)
                            result.success(saved)
                        }
                    }
                    "buyer_request_submitted", "seller_signup_completed" -> {
                        val enabled = preferences.getBoolean("enabled", false)
                        if (enabled) analytics.logEvent(call.method, null)
                        result.success(enabled)
                    }
                    else -> result.notImplemented()
                }
            }
    }

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
