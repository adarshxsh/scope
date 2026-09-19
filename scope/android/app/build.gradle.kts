import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load key.properties if present
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { inputStream ->
        keyProperties.load(inputStream)
    }
}

fun getSigningProperty(propKey: String, vararg envKeys: String): String? {
    val propVal = keyProperties.getProperty(propKey)
    if (!propVal.isNullOrBlank()) {
        return propVal
    }
    for (envKey in envKeys) {
        val propEnvVal = keyProperties.getProperty(envKey)
        if (!propEnvVal.isNullOrBlank()) {
            return propEnvVal
        }
        val envVal = System.getenv(envKey)
        if (!envVal.isNullOrBlank()) {
            return envVal
        }
    }
    val directEnv = System.getenv(propKey)
    if (!directEnv.isNullOrBlank()) {
        return directEnv
    }
    return null
}

val keystoreFilePath = getSigningProperty("storeFile", "ANDROID_KEYSTORE_PATH", "KEYSTORE_FILE")
val keystorePassword = getSigningProperty("storePassword", "ANDROID_KEYSTORE_PASSWORD", "KEYSTORE_PASSWORD")
val keyAlias = getSigningProperty("keyAlias", "ANDROID_KEY_ALIAS", "KEY_ALIAS")
val keyPassword = getSigningProperty("keyPassword", "ANDROID_KEY_PASSWORD", "KEY_PASSWORD")

val keystoreFile = if (!keystoreFilePath.isNullOrBlank()) {
    val fApp = file(keystoreFilePath)
    val fRoot = rootProject.file(keystoreFilePath)
    when {
        fApp.exists() -> fApp
        fRoot.exists() -> fRoot
        else -> fApp
    }
} else {
    null
}

val hasReleaseSigningCredentials = keystoreFile != null &&
    keystoreFile.exists() &&
    !keystorePassword.isNullOrBlank() &&
    !keyAlias.isNullOrBlank() &&
    !keyPassword.isNullOrBlank()

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
        if (hasReleaseSigningCredentials) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keystorePassword
                keyAlias = keyAlias
                keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasReleaseSigningCredentials) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: Release signing credentials not found or incomplete. Falling back to debug signingConfig.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
