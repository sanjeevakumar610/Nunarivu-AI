plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.nunarivu_ai"
    compileSdk = flutter.compileSdkVersion
    // Required by jni + speech_to_text plugins (NDK version must be uniform)
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.nunarivu_ai"
        // LiteRT-LM requires API 24+
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Keep LiteRT-LM classes from being renamed by R8 — the native
            // liblitertlm_jni.so looks up callback methods by their original
            // names at runtime and crashes with NoSuchMethodError without this.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // LiteRT-LM: GPU-accelerated on-device LLM inference (Adreno 710 via OpenCL)
    // Includes kotlinx-coroutines-android:1.9.0 as a transitive dep
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.11.0")
    // Core library desugaring — required by flutter_local_notifications (java.time)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
