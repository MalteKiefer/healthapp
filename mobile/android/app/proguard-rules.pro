# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }

# Flutter references the Play Core split-install APIs only when the app
# uses deferred components. HealthVault does not, so we tell R8 to ignore
# the missing classes instead of pulling in the play-core dependency.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Kotlin metadata
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Keep health data model classes for JSON deserialization
-keep class de.kiefer_networks.healthapp.** { *; }
