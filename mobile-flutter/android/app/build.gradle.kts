import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signing rilis: baca dari android/key.properties (dev lokal) ATAU variabel
// lingkungan (CI). Nama env sengaja sama dengan secret CI Capacitor lama
// (ANDROID_KEYSTORE_PATH/ANDROID_KS_PASS/ANDROID_KEY_ALIAS/ANDROID_KEY_PASS)
// agar 1 keystore + 1 set secret dipakai bersama. Bila tak ada keystore →
// jatuh ke debug signing (mis. `flutter run --release` tanpa keystore).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
fun signingValue(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey) ?: System.getenv(envKey)
val releaseStorePath: String? = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseKeystore = releaseStorePath != null && file(releaseStorePath).exists()

// Tolak build RELEASE tanpa keystore rilis (jangan diam-diam pakai debug key —
// kunci debug publik → auto-update tak bisa menimpa versi lama & merusak model
// keamanan same-signer). Hanya berlaku saat task rilis diminta; debug tak kena.
val wantsReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release") }
if (wantsReleaseBuild && !hasReleaseKeystore) {
    throw GradleException(
        "Build RELEASE tanpa keystore rilis. Isi android/key.properties (dev) atau " +
        "env ANDROID_KEYSTORE_PATH/ANDROID_KS_PASS/ANDROID_KEY_ALIAS/ANDROID_KEY_PASS (CI)."
    )
}

android {
    namespace = "com.tuleh.tuleh_pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Berdampingan dgn app Capacitor lama (com.tuleh.kasir) untuk uji di HP
        // asli. Ganti ke "com.tuleh.kasir" bila hendak MENIMPA app lama via
        // auto-update (butuh keystore sama + versionCode > 910).
        applicationId = "com.tuleh.tuleh_pos"
        minSdk = 29 // Android 10 — samakan dgn build Capacitor lama
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(releaseStorePath!!)
                storePassword = signingValue("storePassword", "ANDROID_KS_PASS")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            // Tanda tangan STABIL bila keystore tersedia (wajib agar auto-update
            // bisa memasang di atas versi lama); jika tidak, debug signing.
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
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
    // FileProvider (androidx.core.content.FileProvider) untuk Auto-Update installer.
    implementation("androidx.core:core-ktx:1.13.1")
}
