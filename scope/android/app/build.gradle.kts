import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = listOf(
    rootProject.file("key.properties"),
    file("key.properties"),
    file("../key.properties")
).firstOrNull { it.exists() }

val keyProperties = Properties()
if (keyPropertiesFile != null && keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

fun getKeystoreProperty(envKeys: List<String>, propKeys: List<String>): String? {
    for (envKey in envKeys) {
        val envVal = System.getenv(envKey)
        if (!envVal.isNullOrBlank()) return envVal
    }
    for (propKey in propKeys) {
        val propVal = keyProperties.getProperty(propKey)
        if (!propVal.isNullOrBlank()) return propVal
    }
    return null
}

val storeFilePath = getKeystoreProperty(
    listOf("ANDROID_KEYSTORE_PATH", "KEYSTORE_PATH", "STORE_FILE", "ANDROID_STORE_FILE"),
    listOf("storeFile", "store_file", "keyStoreFile", "keystoreFile")
)
val storePasswordVal = getKeystoreProperty(
    listOf("ANDROID_KEYSTORE_PASSWORD", "KEYSTORE_PASSWORD", "STORE_PASSWORD", "ANDROID_STORE_PASSWORD"),
    listOf("storePassword", "store_password", "keyStorePassword", "keystorePassword")
)
val keyAliasVal = getKeystoreProperty(
    listOf("ANDROID_KEY_ALIAS", "KEY_ALIAS"),
    listOf("keyAlias", "key_alias")
)
val keyPasswordVal = getKeystoreProperty(
    listOf("ANDROID_KEY_PASSWORD", "KEY_PASSWORD"),
    listOf("keyPassword", "key_password")
)

val resolvedStoreFile = if (!storeFilePath.isNullOrBlank()) {
    val f = file(storeFilePath)
    if (f.isAbsolute && f.exists()) {
        f
    } else if (f.exists()) {
        f
    } else if (rootProject.file(storeFilePath).exists()) {
        rootProject.file(storeFilePath)
    } else {
        f
    }
} else null

val hasReleaseSigning = resolvedStoreFile != null &&
        resolvedStoreFile.exists() &&
        !storePasswordVal.isNullOrBlank() &&
        !keyAliasVal.isNullOrBlank() &&
        !keyPasswordVal.isNullOrBlank()

val requireReleaseSigning = System.getenv("REQUIRE_RELEASE_SIGNING")?.toBoolean() == true ||
        (project.findProperty("REQUIRE_RELEASE_SIGNING") as? String)?.toBoolean() == true ||
        System.getProperty("REQUIRE_RELEASE_SIGNING")?.toBoolean() == true

if (requireReleaseSigning && !hasReleaseSigning) {
    val missing = mutableListOf<String>()
    if (resolvedStoreFile == null || !resolvedStoreFile.exists()) {
        missing.add("storeFile (${storeFilePath ?: "not specified"})")
    }
    if (storePasswordVal.isNullOrBlank()) missing.add("storePassword")
    if (keyAliasVal.isNullOrBlank()) missing.add("keyAlias")
    if (keyPasswordVal.isNullOrBlank()) missing.add("keyPassword")
    throw GradleException("REQUIRE_RELEASE_SIGNING is set to true, but release signing configuration is incomplete. Missing or invalid parameters: ${missing.joinToString(", ")}")
}

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
        val debugConfig = getByName("debug")
        create("release") {
            if (hasReleaseSigning) {
                storeFile = resolvedStoreFile
                storePassword = storePasswordVal
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
            } else {
                logger.info("Release signing credentials not found; falling back to debug signing config.")
                storeFile = debugConfig.storeFile
                storePassword = debugConfig.storePassword
                keyAlias = debugConfig.keyAlias
                keyPassword = debugConfig.keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
