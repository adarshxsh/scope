# ProGuard and R8 Optimization Rules for SCOPE (com.scope.attentions)

# ------------------------------------------------------------------------------
# 1. Flutter Engine & Framework Embedding Keep Rules
# ------------------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve Flutter generated plugin registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Suppress warnings for optional Play Store deferred components
-dontwarn com.google.android.play.core.**

# ------------------------------------------------------------------------------
# 2. Application Entrypoints and Android OS Components
# ------------------------------------------------------------------------------
# Preserve Android OS entrypoints declared in AndroidManifest.xml
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }

# ------------------------------------------------------------------------------
# 3. Serializable Data Models & MethodChannel Bridge Serialization
# ------------------------------------------------------------------------------
# Keep field names and getter methods involved in MethodChannel map conversion (NotificationData.toMap())
-keep class com.scope.attentions.NotificationData {
    public <fields>;
    public <methods>;
}

-keepclassmembers class com.scope.attentions.NotificationData {
    public *** toMap();
    public *** get*();
}

# Preserve all package classes under com.scope.attentions
-keep class com.scope.attentions.** { *; }

# ------------------------------------------------------------------------------
# 4. Native Plugin C/FFI Dependencies
# ------------------------------------------------------------------------------
# TensorFlow Lite / LiteRT (tflite_flutter)
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }
-keep class com.google.android.gms.tflite.** { *; }
-dontwarn org.tensorflow.lite.**

# SQLite Libraries (sqlite3_flutter_libs)
-keep class org.sqlite.** { *; }
-keep class io.simonbinder.sqlite3.** { *; }
-keep class com.sqlite.** { *; }
-dontwarn io.simonbinder.sqlite3.**

# ------------------------------------------------------------------------------
# 5. Native JNI Bridge Signatures & Runtime Reflection Protection
# ------------------------------------------------------------------------------
# Preserve all native methods across the application
-keepclasseswithmembernames class * {
    native <methods>;
}

# Retain stack traces and attributes for production mapping.txt de-obfuscation
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-renamesourcefileattribute SourceFile

# Retain Enum values and valueOf methods
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
