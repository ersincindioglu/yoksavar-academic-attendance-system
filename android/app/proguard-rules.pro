# ═══════════════════════════════════════════════
# ProGuard / R8 kuralları — YokSavar Pro
# ═══════════════════════════════════════════════

# ── Flutter ──
-keep class io.flutter.** { *; }
-keep class com.google.android.play.** { *; }

# ── Firebase ──
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }

# ── Kotlin ──
-keepattributes *Annotation*
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }

# ── MethodChannel (native ↔ Dart köprüsü) ──
-keep class com.example.yoklama_app.MainActivity { *; }

# ── BLE / Bluetooth ──
-keep class android.bluetooth.** { *; }
-keep class android.bluetooth.le.** { *; }

# ── NFC ──
-keep class android.nfc.** { *; }

# ── Supabase HTTP ──
-keepattributes Signature
-keepattributes *Annotation*

# ── Enum'ları koru (MethodChannel callback'leri için) ──
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Flutter Play Store deferred components (kullanılmıyor ama referans var) ──
-dontwarn com.google.android.play.core.**

