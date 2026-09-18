# Suppress warnings for optional Play Store deferred components in Flutter engine
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**

# Flutter Engine & Plugins keep rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Native App Components (MainActivity, NotificationCollectorService, NotificationData)
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }
-keep class com.scope.attentions.NotificationData { *; }
-keep class com.scope.attentions.** { *; }

# Keep data class fields and serialization methods (toMap)
-keepclassmembers class com.scope.attentions.NotificationData {
    public <fields>;
    public <methods>;
}

-keepclassmembers class com.scope.attentions.NotificationCollectorService {
    public static <fields>;
    public static <methods>;
}

# Preserve generic signatures and annotations for reflection/serialization
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
