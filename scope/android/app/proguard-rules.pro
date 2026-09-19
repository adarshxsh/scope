# ProGuard / R8 Rules for SCOPE (AttentionOS)
#
# Rule Maintenance Guidelines for Future Android Native Plugins:
# 1. When adding native plugins or components accessed via JNI or reflection,
#    add explicit '-keep class <package>.** { *; }' rules below.
# 2. Keep MethodChannel handlers and entry point classes intact to prevent
#    runtime NoSuchMethodError / ClassNotFoundException.

# 1. Preserve Kotlin reflection metadata annotations required by Flutter runtime channels
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class kotlin.Metadata { *; }
-keepclassmembers class * {
    @kotlin.jvm.Transient *;
}

# 2. Preserve Flutter engine embedding interfaces to prevent runtime crashes
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }

# 3. Preserve Android application entry points declared in AndroidManifest.xml
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }

# 4. Suppress warnings and preserve third-party dependencies
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitinstall.**
-keep class org.tensorflow.lite.** { *; }
-keep class com.google.android.gms.tflite.** { *; }
-keep class org.sqlite.** { *; }
-keep class io.simonbinder.sqlite3.** { *; }
