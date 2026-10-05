# Keep the ads and billing plugin classes: they are reached reflectively by
# the Flutter plugin registrant on some builds.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.android.billingclient.** { *; }
-keep class com.android.vending.billing.** { *; }
-keep class io.flutter.plugins.** { *; }

# audioplayers uses reflection to pick a player implementation.
-keep class xyz.luan.audioplayers.** { *; }

-dontwarn com.google.android.gms.**
-dontwarn com.android.billingclient.**
