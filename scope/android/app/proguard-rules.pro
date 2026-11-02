# Flutter Engine & Embedding Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.provider.** { *; }
-keep class io.flutter.annotation.** { *; }

-keep @io.flutter.annotation.Keep class * { *; }
-keepclassmembers class * {
    @io.flutter.annotation.Keep *;
}

-dontwarn io.flutter.**

# com.scope.attentions Native Entry Points & Components
-keep class com.scope.attentions.MainActivity { *; }
-keep class com.scope.attentions.NotificationCollectorService { *; }
-keep class com.scope.attentions.NotificationCollectorService$Companion { *; }
-keep class com.scope.attentions.NotificationData { *; }
-keep class com.scope.attentions.NotificationRedactor { *; }
-keep class com.scope.attentions.** { *; }
-keepclassmembers class com.scope.attentions.** { *; }
