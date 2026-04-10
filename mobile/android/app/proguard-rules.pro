# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }

# Kotlin metadata
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Keep health data model classes for JSON deserialization
-keep class de.kiefer_networks.healthapp.** { *; }
