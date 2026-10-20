import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }

android {
    namespace = "com.gymia.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.gymia.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingFile.exists()) create("personal") {
            keyAlias = signingProperties.getProperty("keyAlias")
            keyPassword = signingProperties.getProperty("keyPassword")
            storeFile = file(signingProperties.getProperty("storeFile"))
            storePassword = signingProperties.getProperty("storePassword")
        }
    }
    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        release {
            signingConfig = signingConfigs.findByName("personal")
        }
    }
}

// Never silently distribute an unsigned APK or change its signing identity.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "assembleRelease" } && !signingFile.exists()) {
        throw GradleException("Missing android/key.properties. See README.md for signing setup.")
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.12")
    testImplementation("org.json:json:20180813")
    // Keep Android 6 support; 22.x raises the library's minimum to API 24.
    implementation("com.google.android.gms:play-services-auth:21.5.0")
}
