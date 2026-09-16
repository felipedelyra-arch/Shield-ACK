# ---- Flutter / Dart
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ---- Firebase / Google
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
# Modelos usados por reflexão na serialização do Firestore
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
}

# ---- SQLCipher
-keep class net.sqlcipher.** { *; }
-keep class net.zetetic.** { *; }

# ---- freeRASP: ofuscar as classes de detecção derrota a própria detecção
-keep class com.aheaditec.talsec.** { *; }
-keep class com.aheaditec.freerasp.** { *; }

# ---- local_auth / biometria
-keep class androidx.biometric.** { *; }

# ---- Remove log em release. Uma linha de Log.d com token é um vazamento.
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
