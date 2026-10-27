plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = listOf("NAS_TODO_KEYSTORE_PATH", "NAS_TODO_STORE_PASSWORD", "NAS_TODO_KEY_ALIAS", "NAS_TODO_KEY_PASSWORD")
val signingValues = releaseKeys.map { System.getenv(it).orEmpty() }
require(signingValues.all { it.isBlank() } || signingValues.all { it.isNotBlank() }) { "All four signing values are required" }
val hasReleaseKey = signingValues.all { it.isNotBlank() }

android {
    namespace = "cn.privatetodo.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.privatetodo.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures { buildConfig = true }
    signingConfigs {
        if (hasReleaseKey) create("fixedRelease") {
            storeFile = file(signingValues[0])
            storePassword = signingValues[1]
            keyAlias = signingValues[2]
            keyPassword = signingValues[3]
        }
    }
    buildTypes {
        debug { buildConfigField("boolean", "UPDATES_ENABLED", "false") }
        release {
            buildConfigField("boolean", "UPDATES_ENABLED", hasReleaseKey.toString())
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("fixedRelease")
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
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
