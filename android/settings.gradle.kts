pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Pinned below AGP 9: several plugins we depend on (file_picker among
    // them) skip applying their own Kotlin Gradle Plugin once
    // ANDROID_GRADLE_PLUGIN_VERSION.major >= 9, assuming AGP's built-in
    // Kotlin support compiles their Kotlin sources instead - it doesn't
    // (yet), which leaves classes like FilePickerPlugin uncompiled and
    // breaks the release build. Staying on 8.x keeps that plugin-applied
    // Kotlin path working.
    id("com.android.application") version "8.11.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
}

include(":app")
