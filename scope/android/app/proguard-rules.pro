# SCOPE (AttentionOS) ProGuard and R8 Rules

# Retain attributes for reflection, annotations, signatures, stack traces
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable

# Keep Flutter embedding classes
-keep class io.flutter.** { *; }

# Keep Kotlin runtime metadata
-keep class kotlin.Metadata { *; }

# Ignore warnings from Play Core library if referenced transitively
-dontwarn com.google.android.play.core.**

# Keep Android native app entry points and MethodChannel handlers
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }

# Keep NotificationData and its serialization method toMap()
-keep class com.scope.attentions.NotificationData {
    public <fields>;
    public <methods>;
    public java.util.HashMap toMap();
    *;
}
