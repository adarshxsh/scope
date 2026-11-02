# Flutter embedding keep rules
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**

# Kotlin runtime metadata keep rules
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable
-keep class kotlin.Metadata { *; }

# App entrypoints and service components
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }

# Data model and serialization method
-keep class com.scope.attentions.NotificationData {
    public <fields>;
    public <methods>;
    public java.util.HashMap toMap();
}

# Preserve scope attentions package classes
-keep class com.scope.attentions.** { *; }
