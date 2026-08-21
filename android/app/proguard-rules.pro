# R8 is enabled for release builds (see build.gradle.kts). Flutter's own
# engine classes and the plugins below are reached reflectively or from
# native code, so R8 cannot see the references and would strip them.

# Flutter engine + embedding.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core is referenced by Flutter's deferred-components support even
# when the app does not use deferred components.
-dontwarn com.google.android.play.core.**

# RevenueCat models are deserialized from JSON by name.
-keep class com.revenuecat.purchases.** { *; }

# Keep annotations R8 would otherwise drop, so stack traces from release
# crashes stay useful once a crash reporter is attached.
-keepattributes *Annotation*, InnerClasses, Signature, SourceFile, LineNumberTable
