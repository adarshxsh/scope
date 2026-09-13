plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.scope.attentions"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.scope.attentions"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storeFileEnv = System.getenv("RELEASE_STORE_FILE")
            val storePasswordEnv = System.getenv("RELEASE_STORE_PASSWORD")
            val keyAliasEnv = System.getenv("RELEASE_KEY_ALIAS")
            val keyPasswordEnv = System.getenv("RELEASE_KEY_PASSWORD")

            if (!storeFileEnv.isNullOrBlank()) {
                storeFile = file(storeFileEnv)
            }
            if (!storePasswordEnv.isNullOrBlank()) {
                storePassword = storePasswordEnv
            }
            if (!keyAliasEnv.isNullOrBlank()) {
                keyAlias = keyAliasEnv
            }
            if (!keyPasswordEnv.isNullOrBlank()) {
                keyPassword = keyPasswordEnv
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    val isReleaseRequested = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    if (isReleaseRequested) {
        val storeFileEnv = System.getenv("RELEASE_STORE_FILE")
        val storePasswordEnv = System.getenv("RELEASE_STORE_PASSWORD")
        val keyAliasEnv = System.getenv("RELEASE_KEY_ALIAS")
        val keyPasswordEnv = System.getenv("RELEASE_KEY_PASSWORD")

        val missingVars = mutableListOf<String>()
        if (storeFileEnv.isNullOrBlank()) missingVars.add("RELEASE_STORE_FILE")
        if (storePasswordEnv.isNullOrBlank()) missingVars.add("RELEASE_STORE_PASSWORD")
        if (keyAliasEnv.isNullOrBlank()) missingVars.add("RELEASE_KEY_ALIAS")
        if (keyPasswordEnv.isNullOrBlank()) missingVars.add("RELEASE_KEY_PASSWORD")

        if (missingVars.isNotEmpty()) {
            throw GradleException(
                "Release build failed: missing required release keystore environment variable(s): ${missingVars.joinToString(", ")}. " +
                "Please configure these environment variables for release builds."
            )
        }

        val keystoreFile = file(storeFileEnv!!)
        if (!keystoreFile.exists()) {
            throw GradleException(
                "Release build failed: specified RELEASE_STORE_FILE does not exist at '${keystoreFile.absolutePath}'."
            )
        }
        if (!keystoreFile.isFile || !keystoreFile.canRead()) {
            throw GradleException(
                "Release build failed: specified RELEASE_STORE_FILE at '${keystoreFile.absolutePath}' is not a readable file."
            )
        }
    }
}

flutter {
    source = "../.."
}
