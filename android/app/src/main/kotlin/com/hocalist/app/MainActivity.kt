package com.hocalist.app

import io.flutter.embedding.android.FlutterActivity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import androidx.lifecycle.lifecycleScope
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import com.google.firebase.analytics.FirebaseAnalytics
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hocalist/google_sign_in")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestIdToken") {
                    lifecycleScope.launch { requestGoogleIdToken(result) }
                } else {
                    result.notImplemented()
                }
            }
        if (packageName.endsWith(".jonsdev")) return
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

    private suspend fun requestGoogleIdToken(result: MethodChannel.Result) {
        // This public Web OAuth client is also used by Hocalist's Supabase provider.
        val webClientId = "1069941498557-ceo7vfsopp8q7cjoc6f459s96qvrb456.apps.googleusercontent.com"
        val nonce = UUID.randomUUID().toString()
        val hashedNonce = MessageDigest.getInstance("SHA-256")
            .digest(nonce.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        val option = GetSignInWithGoogleOption.Builder(webClientId)
            .setNonce(hashedNonce)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        try {
            val credential = CredentialManager.create(this).getCredential(this, request).credential
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                val idToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
                result.success(mapOf("idToken" to idToken, "nonce" to nonce))
            } else {
                result.error("authentication_failed", null, null)
            }
        } catch (_: GetCredentialCancellationException) {
            result.success(null)
        } catch (_: NoCredentialException) {
            result.error("google_account_unavailable", null, null)
        } catch (_: GetCredentialException) {
            result.error("google_sign_in_unavailable", null, null)
        } catch (_: GoogleIdTokenParsingException) {
            result.error("authentication_failed", null, null)
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
