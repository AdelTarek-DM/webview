# Keep Flutter and plugin classes required at runtime.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }

# Keep Kotlin metadata (avoid reflection issues in some libs).
-keep class kotlin.Metadata { *; }

