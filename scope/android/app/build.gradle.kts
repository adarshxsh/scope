import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").let {
    if (it.exists()) it else file("key.properties")
}
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { inputStream ->
        keystoreProperties.load(inputStream)
    }
}

fun getSigningProperty(key: String, envKeys: List<String>): String? {
    val prop = keystoreProperties.getProperty(key)
    if (!prop.isNullOrBlank()) return prop
    for (envKey in envKeys) {
        val envVal = System.getenv(envKey)
        if (!envVal.isNullOrBlank()) return envVal
    }
    return null
}

val storeFilePath = getSigningProperty("storeFile", listOf("ANDROID_STORE_FILE", "STORE_FILE", "KEYSTORE_FILE", "storeFile"))
val storePasswordProp = getSigningProperty("storePassword", listOf("ANDROID_STORE_PASSWORD", "STORE_PASSWORD", "KEYSTORE_PASSWORD", "storePassword"))
val keyAliasProp = getSigningProperty("keyAlias", listOf("ANDROID_KEY_ALIAS", "KEY_ALIAS", "KEYSTORE_KEY_ALIAS", "keyAlias"))
val keyPasswordProp = getSigningProperty("keyPassword", listOf("ANDROID_KEY_PASSWORD", "KEY_PASSWORD", "KEYSTORE_KEY_PASSWORD", "keyPassword"))

val storeFileObj = storeFilePath?.let { path ->
    val f = file(path)
    if (f.exists()) f
    else rootProject.file(path).let { if (it.exists()) it else f }
}

val hasReleaseSigning = storeFileObj != null && storeFileObj.exists() &&
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
        if (hasReleaseSigning) {
            create("release") {
                storeFile = storeFileObj
                storePassword = storePasswordProp
                keyAlias = keyAliasProp
                keyPassword = keyPasswordProp
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: Release signing credentials (key.properties or environment variables) not found or incomplete. Falling back to debug signing for local test builds.")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
