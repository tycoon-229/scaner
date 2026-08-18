plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val rustCcaCcbCrateDir = file("src/main/rust/gs1_cca_ccb_scanner")
val rustCcaCcbJniLibsDir = layout.buildDirectory.dir("rustJniLibs/gs1_cca_ccb")
val homeDir = System.getProperty("user.home")
val cargoBinDir = file("$homeDir/.cargo/bin").absolutePath
val rustupHomebrewBinDir = "/opt/homebrew/opt/rustup/bin"
val cargoExecutable = providers.environmentVariable("CARGO")
    .orElse("cargo")

val buildRustCcaCcbScanner by tasks.registering(Exec::class) {
    group = "build"
    description = "Builds the experimental Rust GS1 CC-A/B scanner JNI library."

    workingDir = rustCcaCcbCrateDir
    environment("ANDROID_NDK_HOME", android.ndkDirectory.absolutePath)
    environment("ANDROID_NDK_ROOT", android.ndkDirectory.absolutePath)
    environment("CARGO_TARGET_DIR", layout.buildDirectory.dir("rustTarget/gs1_cca_ccb").get().asFile.absolutePath)
    val pathEntries = listOf(cargoBinDir, rustupHomebrewBinDir, System.getenv("PATH").orEmpty())
        .filter(String::isNotEmpty)
    environment("PATH", pathEntries.joinToString(File.pathSeparator))
    commandLine(
        cargoExecutable.get(),
        "ndk",
        "-t",
        "arm64-v8a",
        "-o",
        rustCcaCcbJniLibsDir.get().asFile.absolutePath,
        "build",
        "--release"
    )

    inputs.dir(rustCcaCcbCrateDir)
    outputs.dir(rustCcaCcbJniLibsDir)
}

android {
    namespace = "com.fpt.yuyama"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fpt.yuyama"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON"
                )
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main").jniLibs.srcDir(rustCcaCcbJniLibsDir)
    }
}

tasks.matching {
    it.name.startsWith("merge") && it.name.endsWith("JniLibFolders")
}.configureEach {
    dependsOn(buildRustCcaCcbScanner)
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
}
