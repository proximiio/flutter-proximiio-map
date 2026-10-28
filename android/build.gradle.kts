group = "io.proximi.flutter_proximiio_map"
version = "6.0.0-beta.4"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// The Proximi.io map and SDK are published to their own Maven repository (public reads, no credentials).
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://maven.eu.proximi.fi/releases/")
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "io.proximi.flutter_proximiio_map"

    // The SDK's AndroidX and OkHttp dependencies require compiling against API 37.
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            all {
                it.useJUnitPlatform()
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Pinned exactly; the map pins the SDK at the version flutter_proximiio uses.
    implementation("io.proximi.map:proximiio-map-live:6.0.0-beta.28")
    implementation("io.proximi.sdk:proximiio:6.0.0-beta.31")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime:2.10.0")

    // The JUnit 5 variant by name: built-in Kotlin does not pick it from useJUnitPlatform().
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
}
