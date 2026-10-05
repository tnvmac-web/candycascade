plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.candycascade.game"
    // 36 because audioplayers_android compiles against it. Both 35 and 36 are
    // installed; targetSdk below is what the store actually cares about.
    compileSdk = 36
    // No NDK: Candy Cascade ships no native code. Every plugin it uses
    // (ads, billing, audioplayers, shared_preferences) is pure Java/Kotlin,
    // so naming an NDK here would only add a multi gigabyte download and a
    // class of build failures for nothing. Add ndkVersion back if you later
    // bring in a plugin with native sources.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.candycascade.game"
        // 23 covers every device Google Play still serves, and the ads and
        // billing SDKs both support it.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        debug {
            // Keeps a debug install side by side with a release one.
            applicationIdSuffix = ".debug"
        }
        release {
            // Signed with the debug key so `flutter run --release` and
            // `flutter build apk --release` work out of the box. Replace this
            // with your own signing config before you upload: the Play Store
            // rejects a debug signed bundle.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
            )
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
