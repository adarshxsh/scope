# ProGuard and R8 rules for SCOPE Android application

# Flutter Engine & Embedding keep rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.view.** { *; }

# Application specific classes, services, and method channel handlers
-keep class com.scope.attentions.** { *; }

# Keep native JNI bindings
-keepclasseswithmembernames class * {
    native <methods>;
}

# TensorFlow Lite
-keep class org.tensorflow.** { *; }
-keepclassmembers class org.tensorflow.** { *; }

# SQLite and Drift bindings
-keep class org.sqlite.** { *; }
-keep class sqlite3.** { *; }

# Suppress warnings for optional Play Core classes referenced by Flutter Engine
-dontwarn com.google.android.play.core.**

# Retain common reflection annotations and signatures
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exceptions
