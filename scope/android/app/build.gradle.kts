import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").takeIf { it.exists() }
    ?: file("key.properties").takeIf { it.exists() }
if (keystorePropertiesFile != null) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun getCredential(propName: String, envVarName: String): String? {
    val propValue = keystoreProperties.getProperty(propName)
    if (!propValue.isNullOrBlank()) {
        return propValue.trim()
    }
    val envValue = System.getenv(envVarName)
    if (!envValue.isNullOrBlank()) {
        return envValue.trim()
    }
    return null
}

val storeFilePath = getCredential("storeFile", "KEYSTORE_FILE")
val storePasswordProp = getCredential("storePassword", "KEYSTORE_PASSWORD")
val keyAliasProp = getCredential("keyAlias", "KEY_ALIAS")
val keyPasswordProp = getCredential("keyPassword", "KEY_PASSWORD")

val resolvedStoreFile = storeFilePath?.let { path ->
    val fileInApp = file(path)
    val fileInRoot = rootProject.file(path)
    when {
        fileInApp.exists() -> fileInApp
        fileInRoot.exists() -> fileInRoot
        else -> fileInApp
    }
}

val releaseSigningConfigured = resolvedStoreFile != null &&
        resolvedStoreFile.exists() &&
        !storePasswordProp.isNullOrBlank() &&
        !keyAliasProp.isNullOrBlank() &&
        !keyPasswordProp.isNullOrBlank()

android {
    namespace = "com.scope.attentions"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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
            if (releaseSigningConfigured) {
                storeFile = resolvedStoreFile
                storePassword = storePasswordProp
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
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
    val hasReleaseTask = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    if (hasReleaseTask && !releaseSigningConfigured) {
        val missingDetails = mutableListOf<String>()
        if (storeFilePath.isNullOrBlank()) missingDetails.add("storeFile / KEYSTORE_FILE")
        else if (resolvedStoreFile == null || !resolvedStoreFile.exists()) missingDetails.add("Keystore file does not exist at '${storeFilePath}'")
        if (storePasswordProp.isNullOrBlank()) missingDetails.add("storePassword / KEYSTORE_PASSWORD")
        if (keyAliasProp.isNullOrBlank()) missingDetails.add("keyAlias / KEY_ALIAS")
        if (keyPasswordProp.isNullOrBlank()) missingDetails.add("keyPassword / KEY_PASSWORD")

        throw GradleException(
            "Release signing configuration is incomplete or missing credentials. " +
            "Please provide credentials in 'key.properties' or via environment variables " +
            "(KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD). " +
            "Missing parameters: ${missingDetails.joinToString(", ")}"
        )
    }
}

flutter {
    source = "../.."
}
