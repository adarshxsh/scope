import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun getSigningProperty(propKey: String, vararg envKeys: String): String? {
    val propValue = keystoreProperties.getProperty(propKey)
    if (!propValue.isNullOrBlank()) {
        return propValue
    }
    for (envKey in envKeys) {
        val envValue = System.getenv(envKey)
        if (!envValue.isNullOrBlank()) {
            return envValue
        }
    }
    return null
}

val storeFilePath = getSigningProperty("storeFile", "ANDROID_KEYSTORE_PATH", "KEYSTORE_FILE", "STORE_FILE")
    ?: keystoreProperties.getProperty("keystoreFile")
val storePasswordVal = getSigningProperty("storePassword", "ANDROID_KEYSTORE_PASSWORD", "KEYSTORE_PASSWORD", "STORE_PASSWORD")
    ?: keystoreProperties.getProperty("keystorePassword")
val keyAliasVal = getSigningProperty("keyAlias", "ANDROID_KEY_ALIAS", "KEY_ALIAS")
val keyPasswordVal = getSigningProperty("keyPassword", "ANDROID_KEY_PASSWORD", "KEY_PASSWORD")

val resolvedStoreFile = storeFilePath?.let { path ->
    val f1 = file(path)
    if (f1.exists()) f1 else {
        val f2 = rootProject.file(path)
        if (f2.exists()) f2 else f1
    }
}

val hasReleaseSigning = resolvedStoreFile != null &&
    resolvedStoreFile.exists() &&
    !storePasswordVal.isNullOrBlank() &&
    !keyAliasVal.isNullOrBlank() &&
    !keyPasswordVal.isNullOrBlank()

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
                storeFile = resolvedStoreFile
                storePassword = storePasswordVal
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null) {
                signingConfig = releaseSigning
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
