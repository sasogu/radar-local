plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Use Android's location provider without a Google Play Services dependency.
configurations.configureEach {
    exclude(group = "com.google.android.gms")
}

val radarReleaseStoreFile = System.getenv("RADAR_RELEASE_STORE_FILE")
val radarReleaseStorePassword = System.getenv("RADAR_RELEASE_STORE_PASSWORD")
val radarReleaseKeyAlias = System.getenv("RADAR_RELEASE_KEY_ALIAS")
val radarReleaseKeyPassword = System.getenv("RADAR_RELEASE_KEY_PASSWORD")
val radarReleaseSigningReady = listOf(
    radarReleaseStoreFile,
    radarReleaseStorePassword,
    radarReleaseKeyAlias,
    radarReleaseKeyPassword,
).all { !it.isNullOrBlank() }

if (!radarReleaseSigningReady && gradle.startParameter.taskNames.any {
        it.contains("Release", ignoreCase = true)
    }) {
    throw GradleException("Release signing environment is required")
}

android {
    namespace = "org.daizan.radar_local"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "org.daizan.radar_local"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (radarReleaseSigningReady) {
            create("radarRelease") {
                storeFile = file(radarReleaseStoreFile!!)
                storePassword = radarReleaseStorePassword
                keyAlias = radarReleaseKeyAlias
                keyPassword = radarReleaseKeyPassword
                storeType = "pkcs12"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (radarReleaseSigningReady) {
                signingConfig = signingConfigs.getByName("radarRelease")
            }
        }
    }
}

flutter {
    source = "../.."
}
