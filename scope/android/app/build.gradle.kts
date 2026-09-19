import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun getPropOrEnv(propKey: String, envKey: String): String? {
    val propVal = keystoreProperties.getProperty(propKey)?.trim()
    if (!propVal.isNullOrEmpty()) return propVal
    val envVal = System.getenv(envKey)?.trim()
    if (!envVal.isNullOrEmpty()) return envVal
    return null
}

val storeFilePath = getPropOrEnv("storeFile", "ANDROID_KEYSTORE_PATH")
val storePasswordVal = getPropOrEnv("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val keyAliasVal = getPropOrEnv("keyAlias", "ANDROID_KEY_ALIAS")
val keyPasswordVal = getPropOrEnv("keyPassword", "ANDROID_KEY_PASSWORD")

val storeFileObj = storeFilePath?.let { path ->
    val f = file(path)
    if (f.exists()) f else rootProject.file(path)
}

val hasReleaseSigning = !storeFilePath.isNullOrBlank() &&
    !storePasswordVal.isNullOrBlank() &&
    !keyAliasVal.isNullOrBlank() &&
    !keyPasswordVal.isNullOrBlank() &&
    storeFileObj != null && storeFileObj.exists()

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
        if (hasReleaseSigning) {
            create("release") {
                storeFile = storeFileObj
                storePassword = storePasswordVal
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: Release signing credentials not found. Falling back to debug signing keys.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

