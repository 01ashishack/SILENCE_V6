import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is loaded from android/key.properties when that file is
// present (it, and any *.jks / *.keystore, are gitignored). When it is absent
// the release build falls back to debug signing, so `flutter run` /
// `flutter build` keep working locally without any secret on disk.
// See android/key.properties.example for the format + how to generate a keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.silence.app.silence"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.silence.app.silence"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only define the release config when key.properties exists, otherwise
        // referencing the (missing) properties would fail configuration.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sign with the real upload keystore when key.properties is present.
            // When it is absent: fail-fast in CI / when release signing is
            // explicitly required (so we never ship a debug-signed release by
            // accident), but keep the debug fallback for local `flutter run`.
            // Opt in to the strict check with `-PrequireReleaseSigning=true` or a
            // CI environment (CI=true). (audit A2-19)
            val requireReleaseSigning =
                (project.findProperty("requireReleaseSigning") == "true") ||
                    (System.getenv("CI") == "true")
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else if (requireReleaseSigning) {
                throw GradleException(
                    "Release signing required but android/key.properties is missing. " +
                        "Generate a keystore and create key.properties " +
                        "(see android/key.properties.example), or drop the " +
                        "requireReleaseSigning flag for a local debug-signed build."
                )
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backports java.time etc. for flutter_local_notifications on older Android.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
