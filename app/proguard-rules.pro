# Stash Audio Player - Production ProGuard Rules
# Optimized for performance and security while maintaining functionality

# ===== DEBUGGING AND CRASH REPORTING =====
# Keep source file names and line numbers for crash reports
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep stack traces readable
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,AnnotationDefault

# ===== AUDIO AND MEDIA =====
# Keep ExoPlayer classes - critical for playback
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep AudioManager and audio effects
-keep class android.media.audiofx.** { *; }
-keep class android.media.AudioManager** { *; }
-keep class android.media.session.** { *; }

# Keep our custom audio classes
-keep class com.stash.opusplayer.audio.** { *; }
-keep class com.stash.opusplayer.service.MusicService { *; }
-keep class com.stash.opusplayer.player.** { *; }

# Keep equalizer enums
-keep enum com.stash.opusplayer.audio.** { *; }

# ===== UI AND APPEARANCE =====
# Keep Glide classes for image loading
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
 <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-keep class com.bumptech.glide.load.data.ParcelFileDescriptorRewinder$InternalRewinder {
  *** rewind();
}

# Keep custom views and animations
-keep class com.stash.opusplayer.ui.** { *; }
-keep class com.stash.opusplayer.utils.AnimationUtils { *; }
-keep class com.stash.opusplayer.utils.UIPerformanceOptimizer { *; }

# Keep appearance preferences
-keep class com.stash.opusplayer.ui.appearance.** { *; }

# ===== DATA AND DATABASE =====
# Keep Room database classes
-keep class androidx.room.** { *; }
-keep class com.stash.opusplayer.data.** { *; }
-keepclassmembers class com.stash.opusplayer.data.** {
    @androidx.room.* <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator *;
}

# ===== CLOUD AND SYNC =====
# Keep AWS SDK classes
-keep class com.amazonaws.** { *; }
-dontwarn com.amazonaws.**
-dontwarn org.apache.commons.**
-dontwarn org.apache.http.**

# Keep cloud service classes
-keep class com.stash.opusplayer.cloud.** { *; }

# ===== NETWORKING =====
# Keep Retrofit and OkHttp
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-dontwarn retrofit2.**
-dontwarn okhttp3.**

# Keep JSON serialization
-keep class com.google.gson.** { *; }
-keep class org.json.** { *; }

# YouTube API
-keep class com.google.api.** { *; }
-dontwarn com.google.api.**

# ===== PERMISSIONS AND SYSTEM =====
# Keep permission handling
-keep class com.karumi.dexter.** { *; }

# Keep Work Manager
-keep class androidx.work.** { *; }
-keep class com.stash.opusplayer.work.** { *; }

# ===== OPTIMIZATION RULES =====
# Remove logging in release builds
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}

# Optimize enums (R8 handles this automatically)

# Remove unused resources
-dontwarn **

# ===== REFLECTION AND ANNOTATIONS =====
# Keep annotations for runtime
-keepattributes *Annotation*
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations

# Keep generic signatures for collections
-keepattributes Signature

# ===== NATIVE CODE =====
# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# ===== CRASH PREVENTION =====
# Don't warn about missing platform classes
-dontwarn java.lang.invoke.**
-dontwarn java.nio.file.**
-dontwarn org.codehaus.mojo.animal_sniffer.**

# Keep classes with specific constructors
-keepclassmembers class * {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# ===== SECURITY =====
# Obfuscate sensitive classes but keep functionality
-keep,allowobfuscation class com.stash.opusplayer.BuildConfig
-keep class com.stash.opusplayer.BuildConfig {
    java.lang.String YOUTUBE_API_KEY;
}

# ===== FINAL OPTIMIZATIONS =====
# Enable all optimizations
-optimizations !code/simplification/arithmetic,!field/*,!class/merging/*,!code/allocation/variable

# Reduce APK size
-repackageclasses ''
-allowaccessmodification
