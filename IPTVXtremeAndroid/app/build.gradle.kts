import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Build-machine secrets (release signing) come from the repository-root `.env`
// file, overridable by real environment variables (for CI). They are only read
// by Gradle at build time — nothing from `.env` is packaged into the APK.
// Subscription credentials never belong here: users enter them in the app.
val repoRoot: File = rootProject.projectDir.parentFile
val dotEnv = Properties().apply {
    val f = File(repoRoot, ".env")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun secret(name: String): String? = (System.getenv(name) ?: dotEnv.getProperty(name))?.trim()?.removeSurrounding("\"")?.ifEmpty { null }

val keystorePath = secret("ANDROID_KEYSTORE_FILE")
val keystoreFile = keystorePath?.let { p -> File(p).let { if (it.isAbsolute) it else File(repoRoot, p) } }

android {
    namespace = "com.iptvxtreme.player"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.iptvxtreme.player"
        minSdk = 26          // Android 8.0 Oreo
        targetSdk = 36
        versionCode = 2
        versionName = "1.1"
    }

    signingConfigs {
        if (keystoreFile != null && keystoreFile.exists()) {
            create("release") {
                storeFile = keystoreFile
                storePassword = secret("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = secret("ANDROID_KEY_ALIAS")
                keyPassword = secret("ANDROID_KEY_PASSWORD")
            }
        } else {
            logger.warn("Release signing not configured (.env ANDROID_KEYSTORE_*); release APKs use the debug key.")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isDebuggable = false
            isJniDebuggable = false
        }
    }

    // One universal APK plus smaller per-CPU APKs (libVLC ships native code per ABI).
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
            isUniversalApk = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }

    testOptions { unitTests.isReturnDefaultValues = true }

    packaging {
        jniLibs { useLegacyPackaging = true }
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")

    implementation("org.videolan.android:libvlc-all:3.7.7")

    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}
