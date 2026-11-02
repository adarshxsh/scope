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

fun getSigningProperty(propKey: String, envKey: String): String? {
    val propVal = keystoreProperties.getProperty(propKey)?.takeIf { it.isNotBlank() }
    if (propVal != null) {
        return propVal
    }
    return System.getenv(envKey)?.takeIf { it.isNotBlank() }
}

val storeFilePath = getSigningProperty("storeFile", "ANDROID_KEYSTORE_PATH")
val storePasswordVal = getSigningProperty("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val keyAliasVal = getSigningProperty("keyAlias", "ANDROID_KEY_ALIAS")
val keyPasswordVal = getSigningProperty("keyPassword", "ANDROID_KEY_PASSWORD")

val resolvedStoreFile = storeFilePath?.let { path ->
    val f = file(path)
    if (f.exists()) f else {
        val rootF = rootProject.file(path)
        if (rootF.exists()) rootF else f
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
