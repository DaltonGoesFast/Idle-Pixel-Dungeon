plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.0.21"
}

// JDK 17 language level. The Gradle JVM can be newer (the repo's cloud build used 21).
// compileOnly: Godot is already in the exported game. Do not package a second copy.
base {
    archivesName.set("PatrolWidget")
}

android {
    namespace = "com.daltongoesfast.spdtactics.patrol"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
}
