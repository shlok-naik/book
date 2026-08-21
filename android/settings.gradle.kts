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
    id("com.android.application") version "9.0.1" apply false
    // START: FlutterFire Configuration
    // Bumped from the 4.3.15 the FlutterFire CLI writes by default —
    // that release predates AGP 8, and this project is on AGP 9.
    id("com.google.gms.google-services") version("4.4.4") apply false
    // Uploads the R8 mapping file on every release build, which is the
    // only reason an obfuscated Android stack trace is readable in the
    // Crashlytics console. Not added by the FlutterFire CLI.
    id("com.google.firebase.crashlytics") version("3.0.7") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
