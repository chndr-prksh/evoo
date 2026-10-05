plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The speech engine (sherpa-onnx, Apache-2.0) ships as an .aar on GitHub, not on Maven: scripts in CI (and
// android/README.md) download it to app/libs/ and check its SHA-256.
val buildNumber = (System.getenv("EVOO_BUILD") ?: "1").toInt()

android {
    namespace = "app.evoo.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.evoo.android"
        minSdk = 26
        targetSdk = 35
        versionCode = buildNumber
        versionName = "0.1.$buildNumber"
        // Phones from the last ~8 years are all 64-bit ARM; skipping the other three keeps the download small.
        ndk { abiFilters += listOf("arm64-v8a") }
        externalNativeBuild { cmake { arguments += listOf("-DCMAKE_BUILD_TYPE=Release", "-DANDROID_STL=c++_static") } }
    }

    // llama.cpp for the small polish model (src/main/cpp).
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }

    signingConfigs {
        // A stable key when CI provides one (so updates install over the old version); otherwise the debug key.
        create("release") {
            val store = System.getenv("EVOO_KEYSTORE")
            if (store != null) {
                storeFile = file(store)
                storePassword = System.getenv("EVOO_KEYSTORE_PASSWORD")
                keyAlias = "evoo"
                keyPassword = System.getenv("EVOO_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (System.getenv("EVOO_KEYSTORE") != null) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { buildConfig = true }
}

dependencies {
    implementation(project(":core"))
    implementation(files("libs/sherpa-onnx.aar"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    // Google's on-device AI (Gemini Nano) for polish, on phones that have it.
    implementation("com.google.mlkit:genai-proofreading:1.0.0-beta1")
}
