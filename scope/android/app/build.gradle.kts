import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties from key.properties file or environment variables
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties").let {
    if (it.exists()) it else file("key.properties")
}

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { input ->
        keystoreProperties.load(input)
    }
}

fun getKeystoreProp(propName: String, altPropName: String, envName: String): String? {
    return keystoreProperties.getProperty(propName)
        ?: keystoreProperties.getProperty(altPropName)
        ?: System.getenv(envName)
}

val storeFilePath = getKeystoreProp("storeFile", "store_file", "ANDROID_KEYSTORE_PATH")
val storePasswordVal = getKeystoreProp("storePassword", "store_password", "ANDROID_KEYSTORE_PASSWORD")
val keyAliasVal = getKeystoreProp("keyAlias", "key_alias", "ANDROID_KEY_ALIAS")
val keyPasswordVal = getKeystoreProp("keyPassword", "key_password", "ANDROID_KEY_PASSWORD")

val hasReleaseSigningProps = !storeFilePath.isNullOrBlank() &&
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
        if (hasReleaseSigningProps) {
            create("release") {
                val resolvedStoreFile = if (File(storeFilePath!!).isAbsolute) {
                    File(storeFilePath)
                } else if (file(storeFilePath).exists()) {
                    file(storeFilePath)
                } else if (rootProject.file(storeFilePath).exists()) {
                    rootProject.file(storeFilePath)
                } else {
                    file(storeFilePath)
                }

                if (!resolvedStoreFile.exists()) {
                    throw GradleException("Release signing configuration error: Keystore file defined in key.properties or environment variable does not exist at '${resolvedStoreFile.absolutePath}'")
                }

                storeFile = resolvedStoreFile
                storePassword = storePasswordVal
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigningProps) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                val isCiEnv = System.getenv("CI")?.let { it.isNotBlank() && it.lowercase() != "false" && it != "0" } ?: false
                val isStrictProp = (project.hasProperty("requireReleaseKey") && project.findProperty("requireReleaseKey")?.toString()?.lowercase() != "false") ||
                        (project.hasProperty("strictSigning") && project.findProperty("strictSigning")?.toString()?.lowercase() != "false")
                val isStrictEnv = System.getenv("REQUIRE_RELEASE_KEY")?.lowercase() == "true" || System.getenv("FAIL_ON_MISSING_KEYSTORE")?.lowercase() == "true"

                if (isCiEnv || isStrictProp || isStrictEnv) {
                    throw GradleException("Release build failed: Release signing credentials are missing (key.properties / environment variables), but release signing is required in CI or strict release mode.")
                } else {
                    println("Warning: key.properties not found or incomplete. Gracefully falling back to debug signing for local development.")
                    signingConfig = signingConfigs.getByName("debug")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
