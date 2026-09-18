import java.io.File
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
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

fun getProp(envName: String, propName1: String, propName2: String): String? {
    val envVal = System.getenv(envName)?.takeIf { it.isNotBlank() }
    if (envVal != null) return envVal
    val p1 = keystoreProperties.getProperty(propName1)?.takeIf { it.isNotBlank() }
    if (p1 != null) return p1
    val p2 = keystoreProperties.getProperty(propName2)?.takeIf { it.isNotBlank() }
    if (p2 != null) return p2
    return null
}

val keystoreFilePath = getProp("KEYSTORE_FILE", "storeFile", "KEYSTORE_FILE")
val keystorePasswordVal = getProp("KEYSTORE_PASSWORD", "storePassword", "KEYSTORE_PASSWORD")
val keyAliasVal = getProp("KEY_ALIAS", "keyAlias", "KEY_ALIAS")
val keyPasswordVal = getProp("KEY_PASSWORD", "keyPassword", "KEY_PASSWORD")

val resolvedKeystoreFile: File? = if (!keystoreFilePath.isNullOrBlank()) {
    val fileInRoot = rootProject.file(keystoreFilePath)
    if (fileInRoot.exists()) {
        fileInRoot
    } else {
        val fileInProject = file(keystoreFilePath)
        if (fileInProject.exists()) {
            fileInProject
        } else {
            fileInRoot
        }
    }
} else {
    null
}

val missingProperties = mutableListOf<String>()
if (keystoreFilePath.isNullOrBlank()) {
    missingProperties.add("KEYSTORE_FILE / storeFile")
} else if (resolvedKeystoreFile == null || !resolvedKeystoreFile.exists()) {
    missingProperties.add("Keystore file does not exist at '${keystoreFilePath}'")
}
if (keystorePasswordVal.isNullOrBlank()) {
    missingProperties.add("KEYSTORE_PASSWORD / storePassword")
}
if (keyAliasVal.isNullOrBlank()) {
    missingProperties.add("KEY_ALIAS / keyAlias")
}
if (keyPasswordVal.isNullOrBlank()) {
    missingProperties.add("KEY_PASSWORD / keyPassword")
}

val isSigningConfigured = missingProperties.isEmpty()

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
            if (isSigningConfigured && resolvedKeystoreFile != null) {
                this.storeFile = resolvedKeystoreFile
                this.storePassword = keystorePasswordVal
                this.keyAlias = keyAliasVal
                this.keyPassword = keyPasswordVal
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
    val isReleaseTaskRequested = allTasks.any { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    if (isReleaseTaskRequested && !isSigningConfigured) {
        throw GradleException(
            "Release signing credentials are incomplete or missing.\n" +
            "Missing or invalid release signing properties:\n" +
            missingProperties.joinToString("\n") { "  - $it" } + "\n\n" +
            "Please provide release signing credentials via environment variables:\n" +
            "  - KEYSTORE_FILE\n" +
            "  - KEYSTORE_PASSWORD\n" +
            "  - KEY_ALIAS\n" +
            "  - KEY_PASSWORD\n" +
            "or define them in 'android/key.properties':\n" +
            "  - storeFile\n" +
            "  - storePassword\n" +
            "  - keyAlias\n" +
            "  - keyPassword"
        )
    }
}

flutter {
    source = "../.."
}
