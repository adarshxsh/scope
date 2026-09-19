# ProGuard / R8 rules for Scope Android App

# Preserve Flutter embedding and engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.android.** { *; }
-keep class io.flutter.embedding.engine.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep application package components and data models used in MethodChannel
-keep class com.scope.attentions.** { *; }
-keepclassmembers class com.scope.attentions.** { *; }

# Explicitly keep Android entry points and MethodChannel models
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }
-keep class com.scope.attentions.NotificationData {
    public <fields>;
    public <methods>;
}

# Retain annotations and class metadata
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Suppress warnings from Google Play Core / SplitInstall if present in Flutter dependencies
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitinstall.**
