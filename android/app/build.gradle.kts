plugins {
    id("com.android.application")
    // Explicitly applied (rather than relying on AGP's built-in Kotlin
    // support) so the `kotlin { compilerOptions { ... } }` block below
    // works with AGP 8.x - see settings.gradle.kts for why we're pinned
    // to 8.x.
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rideatlas.rideatlas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.rideatlas.rideatlas"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // A committed, stable keystore - NOT Android's default auto-generated
    // debug.keystore. That default is regenerated (with a new random key)
    // whenever it doesn't already exist on the build machine, which is
    // every single time on a fresh CI runner - so every CI-built APK ended
    // up signed with a different key, and Android refuses to install an
    // update over an app signed with a different key. This is a
    // sideload-only key (not for the Play Store), so committing it is fine,
    // the same way Android's own debug.keystore ships with a
    // publicly-known password.
    signingConfigs {
        create("release") {
            storeFile = file("rideatlas-debug.keystore")
            storePassword = "rideatlas123"
            keyAlias = "rideatlas"
            keyPassword = "rideatlas123"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Android Auto: lets a recording be started/paused/finished and its
    // live stats be read from the car's head unit screen, via the native
    // screens in android/app/src/main/kotlin/.../car/.
    implementation("androidx.car.app:app:1.4.0")
    // Native recording foreground service (see RecordingLocationService.kt).
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // WGS84 ellipsoid → Mean Sea Level altitude (see RecordingLocationService).
    implementation("androidx.core:core-location-altitude:1.0.0")
}

flutter {
    source = "../.."
}
