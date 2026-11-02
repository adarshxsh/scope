# Custom ProGuard keep rules for Scope (AttentionOS)

# Flutter framework and engine JNI bindings
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }

# Android OS Entry Points and Services
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }

# Native Kotlin classes and MethodChannel data models
-keep class com.scope.attentions.** { *; }
-keepclassmembers class com.scope.attentions.** { *; }

# TensorFlow Lite native bindings
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
-keep class com.google.android.gms.tflite.** { *; }
-dontwarn com.google.android.gms.tflite.**

# SQLite native libraries (Drift / sqlite3_flutter_libs)
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**
-keep class io.simonbinder.sqlite3.** { *; }
-dontwarn io.simonbinder.sqlite3.**

# Suppress unreferenced Play Core library warnings
-dontwarn com.google.android.play.core.**

# Preserve source file attributes and line numbers for stack trace de-obfuscation
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable,*Annotation*
