import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services") apply false
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val hocalistJonsDev = System.getenv("HOCALIST_JONS_DEV") == "true"
val flutterTarget = (project.findProperty("target") as String?)?.replace('\\', '/')
val jonsDevTarget = flutterTarget?.endsWith("tool/jons_dev.dart") == true
if (hocalistJonsDev != jonsDevTarget) {
    throw GradleException("Use HOCALIST_JONS_DEV=true with tool/jons_dev.dart for Jon's Dev.")
}
if (!hocalistJonsDev) {
    apply(plugin = "com.google.gms.google-services")
}

// Maps SDK for Android credential injection contract.
//
// The restricted development key is read from the environment variable
// HOCALIST_GOOGLE_MAPS_ANDROID_API_KEY or from `local.properties` under the
// same name. Never commit the value; an empty placeholder keeps prototype
// builds working without a map key. iOS Maps credentials stay deferred per
// the owner and are not configured here.
val hocalistLocalProperties = Properties().apply {
    val configurationFile = rootProject.file("local.properties")
    if (configurationFile.exists()) {
        configurationFile.inputStream().use { load(it) }
    }
}
val hocalistMapsApiKey: String = sequenceOf(
    System.getenv("HOCALIST_GOOGLE_MAPS_ANDROID_API_KEY"),
    project.findProperty("HOCALIST_GOOGLE_MAPS_ANDROID_API_KEY") as String?,
    hocalistLocalProperties.getProperty("HOCALIST_GOOGLE_MAPS_ANDROID_API_KEY"),
).firstOrNull { !it.isNullOrBlank() } ?: ""

// Release credentials are supplied by the packaging environment, never source.
val hocalistReleaseStore = System.getenv("HOCALIST_RELEASE_STORE_FILE")
val hocalistReleaseStorePassword = System.getenv("HOCALIST_RELEASE_STORE_PASSWORD")
val hocalistReleaseAlias = System.getenv("HOCALIST_RELEASE_KEY_ALIAS")
val hocalistReleaseKeyPassword = System.getenv("HOCALIST_RELEASE_KEY_PASSWORD")
val hocalistReleaseSigningReady = listOf(
    hocalistReleaseStore, hocalistReleaseStorePassword,
    hocalistReleaseAlias, hocalistReleaseKeyPassword,
).all { !it.isNullOrBlank() }
val hocalistReleaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (hocalistReleaseRequested && !hocalistReleaseSigningReady) {
    throw GradleException("Hocalist release signing is not configured. Supply all HOCALIST_RELEASE_* signing variables; use a debug build for local testing.")
}
if (hocalistJonsDev && hocalistReleaseRequested) {
    throw GradleException("Jon's Dev is a debug-only build.")
}

android {
    namespace = "com.hocalist.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hocalist.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["HOCALIST_MAPS_API_KEY"] = hocalistMapsApiKey
        manifestPlaceholders["HOCALIST_APP_LABEL"] = "Hocalist"
        manifestPlaceholders["HOCALIST_CALLBACK_SCHEME"] = "com.hocalist.app"
    }

    signingConfigs {
        if (hocalistReleaseSigningReady) {
            create("hocalistRelease") {
                storeFile = file(hocalistReleaseStore!!)
                storePassword = hocalistReleaseStorePassword
                keyAlias = hocalistReleaseAlias
                keyPassword = hocalistReleaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            if (hocalistJonsDev) {
                applicationIdSuffix = ".jonsdev"
                manifestPlaceholders["HOCALIST_APP_LABEL"] = "Hocalist – Jon's Dev"
                manifestPlaceholders["HOCALIST_CALLBACK_SCHEME"] = "com.hocalist.app.jonsdev"
                manifestPlaceholders["HOCALIST_MAPS_API_KEY"] = ""
            }
        }
        release {
            signingConfig = signingConfigs.findByName("hocalistRelease")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Keep aligned with the existing firebase_core Android SDK version.
    implementation(platform("com.google.firebase:firebase-bom:34.19.0"))
    implementation("com.google.firebase:firebase-analytics")
}
