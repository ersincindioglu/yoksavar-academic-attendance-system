# YOKSAVAR PRO — Akıllı Yoklama Sistemi

Flutter (Dart) tabanlı, çok faktörlü (biyometrik + NFC + BLE + dinamik token) akademik yoklama uygulaması. Backend: Supabase (PostgREST + Edge Functions). Bildirim: Firebase Cloud Messaging.

## Hızlı yönlendirme

- **Tüm UI + iş mantığı**: `lib/main.dart` (~1900 satır, tek dosya). Yeni özellik bu dosyaya eklenir, çoklu-dosyaya bölme — proje bilinçli olarak tek dosya tutuluyor.
- **Cihaz UID yardımcısı**: `lib/device_service.dart` — `DeviceService.getDeviceUID()` Android `androidInfo.id` / iOS `identifierForVendor` döner. Cihaz mühürlemesi için kullanılır.
- **Firebase konfigürasyonu**: `lib/firebase_options.dart` (otomatik üretilmiş, elle düzenleme).
- **Android native köprüleri**: `android/app/src/main/kotlin/com/example/yoklama_app/MainActivity.kt` — `MethodChannel`'lar: `yoklama/nfc` (scanUid), `yoklama/ble` (requestPermissions, startAdvertising, stopAdvertising), `yoklama/notifications` (createNotificationChannel).
- **Supabase Edge Function**: `supabase/functions/send-attendance-notification/index.ts` — oturum kapatıldığında devamsızlık bildirimi gönderir (FCM üzerinden).

## Mimari özet (main.dart bölümleri)

Dosya `/* ═══ */` yorum bloklarıyla bölünmüş. Anahtar sınıflar ve satır numaraları:

1. **SABİTLER** (l. 15–24): `supabaseUrl`, `supabaseAnonKey` (`.env` dosyasından `flutter_dotenv` ile yüklenir), `kNfcChannel`, `kBleChannel`, `kServiceUuid`, `kManufacturerId`. `.env` git-ignore edilir, `.env.example` template olarak committe.
2. **TEMA YÖNETİMİ** (l. 26–50): `themeNotifier` (`ValueNotifier<ThemeMode>`) + `YT` sınıfı — koyu/açık tema için tüm renkleri context'ten türetir. UI eklerken renk seçerken sabit `Color(...)` yerine `YT.bg(c)`, `YT.cardBg(c)`, `YT.textPrimary(c)` vb. kullan.
3. **BAŞLATMA** (l. 73–131): `main()` → Firebase init + native bildirim kanalı + `runApp(YoklamaApp())`. `YoklamaApp` `themeNotifier`'a abone, home = `RoleSelectPage`.
4. **FCMHelper** (l. 136–195): `initFCM(tc)` izin ister, token alır ve `fcm_tokens` tablosuna (`student_tc_no` + `device_uid` PK) upsert eder. Foreground bildirimi dialog olarak gösterir. Background handler `_firebaseMessagingBackgroundHandler` (l. 77).
5. **RoleSelectPage** (l. 200–366): İki rol — Akademisyen (parola `"p"`) ve Öğrenci. Parola değiştirmek için `_showAuth` içindeki iki yerde `"p"` karşılaştırması var.
6. **TeacherPage / _TeacherPageState** (l. 371–913): Ders seçimi (`courses` tablosu) → oturum başlat → BLE advertise (`_startBle`) + 4 sn'de bir `attendance` polling (`_fetchAttendance`) → oturum kapat (Edge Function tetiklenir). BLE durumu `_isAdvertising` ile UI'da gösterilir (`_liveView` içinde).
7. **StudentPage / _StudentPageState** (l. 915+): 4 adımlı akış. Önemli metodlar:
   - `_step1()` (l. 1007) — biyometrik. `PlatformException` yakalanır, `_biometricErrorMsg()` (l. 1038) ile koda göre Türkçe mesaja çevrilir.
   - `_step2Scan()` / `_step2Manual()` (l. 1083, 1096) — NFC okut veya manuel UID gir.
   - `_step3()` (l. 1209) — BLE tarama. **İki aşamalı**: önce `_bleScanFiltered(12)` (l. 1136), bulunamazsa `_bleScanWide(8)` (l. 1175). Detay aşağıda.
   - `_submit()` (l. 1254) — enrollment kontrolü → cihaz mühürleme → mükerrer kontrol → `attendance` kaydı.
   - `_bleStatusBadge()` (l. 1691) — BLE açık/kapalı/tarama rozeti (öğrenci panelinde Step 3 üstünde).

## BLE tarama mantığı (kritik)

**Sorun**: Android 12+ (API 31+) cihazlarda (Samsung A55, Redmi Note 12, Xiaomi 13 vb.) filtresiz `startScan()` çağrıları **scan throttling**'e tabi — sistem saniyede sınırlı sayıda sonuç döner, çoğu cihaz hiçbir DERS sinyali yakalayamaz.

**Çözüm — iki aşamalı tarama (`_step3` içinde)**:

| Aşama | Süre | Yöntem | Hedef cihaz |
|---|---|---|---|
| 1 | 12 sn | `withServices: [Guid(kServiceUuid)]` (donanım filtreli) | Android 12+/yeni cihazlar — throttling'e tabi DEĞİL |
| 2 | 8 sn | Filtresiz fallback | UUID filtresi bozuk eski cihazlar (Android 10-11) |

Her aşama `Completer<void>` + `Future.any([done.future, Future.delayed(...)])` ile **erken çıkış** yapar — bulunduğu an taramayı durdurup döner. Ortalama tarama süresi 2-5 sn.

**`_extractDersName()` (l. 1117)** bir tarama sonucundan "DERS-XXX" adını **üç farklı yolla** arar (Android cihazları manufacturer data / scan response / device name'i tutarsız budar):
1. `manufacturerData[kManufacturerId]`
2. `serviceUuids` UUID eşleşmesi + mf data
3. `device.platformName` / `advertisementData.advName`

**BLE adapter state**: `_StudentPageState.initState` içinde `FlutterBluePlus.adapterState.listen` ile dinlenir, `_bleAdapterState`'e yazılır, `dispose` içinde abonelik iptal edilir. `_bleStatusBadge` widget'ı BLE açık/kapalı/tarama durumunu gösterir.

**Lokasyon servisi**: Android 12+'da `BLUETOOTH_SCAN` izninin manifest'te `usesPermissionFlags="neverForLocation"` flag'i **yok** — bu yüzden bazı cihazlarda (MIUI/HyperOS) lokasyon servisi açık olmadan tarama yapmıyor. Test edilen Xiaomi 13'te lokasyon manuel açıldıktan sonra çalıştı. Eğer ileride manifest'e flag eklenirse `_step3` içindeki "lokasyon açık mı" yönlendirmesi güncellenmeli.

## Supabase tabloları (kullanım haritası)

| Tablo | Anahtar alanlar | Nerede kullanılır |
|---|---|---|
| `courses` | `course_code`, `course_name`, `course_type`, `teacher_name`, `absence_limit` | Akademisyen panelinde ders seçimi (`_loadCourses`) |
| `sessions` | `session_id`, `course_code`, `course_name`, `dynamic_token`, `session_number`, `is_closed` | Oturum başlat/kapat, öğrenci doğrulaması |
| `enrollments` | `student_tc_no`, `course_code`, `full_name` | Öğrenci submit'te derse kayıt kontrolü |
| `profiles` | `student_tc_no` (PK), `full_name`, `registered_device_uid`, `registered_nfc_uid`, `is_registered` | Cihaz + NFC mühürleme; ilk kullanımda upsert, sonraki kullanımda kontrol |
| `attendance` | `session_id`, `student_id`, `full_name`, `device_uid`, `nfc_uid` | Yoklama kaydı (mükerrer kontrol session_id+student_id) |
| `fcm_tokens` | `student_tc_no`, `device_uid` (composite), `fcm_token` | Push bildirim için token kaydı |

## Bilinçli tasarım kararları (değiştirmeden önce sor)

- **Tek dosya**: `main.dart` ~1900 satır — kullanıcı bunu bilerek tutuyor. Refactor önerme, çoklu dosyaya bölme.
- **Türkçe UI metinleri**: Tüm metinler ve durum mesajları Türkçe; emojiler bilinçli (✅ ❌ ⚠️ 🎉 📡 🔒 📶). Yeni metin eklerken aynı stili koru.
- **`withOpacity` kullanımı**: Flutter `.withValues()` deprecated uyarısı veriyor ama proje boyunca `withOpacity` kullanılıyor. Yalnızca dokunulan satırlarda değiştirme — büyük migrate yapma. `flutter analyze` çıktısındaki ~50+ `deprecated_member_use` uyarısı **normal**.
- **Cihaz mühürlemesi**: Bir TC bir cihaza bağlanır (`registered_device_uid`). Değişiklik için admin müdahalesi gerekiyor — bu bir özellik, bug değil.
- **NFC manuel mod**: NFC desteklenmeyen cihazlar için fallback. UID manuel girilebilir (`_nfcManualMode`).
- **BLE advertisement adı**: `DERS-<timestamp>` formatında (öğretmen tarafında `_startSession` içinde üretilir). Öğrenci tarafı manufacturer data, service UUID, ve advertised name'i (üç ayrı yolla) kontrol eder.
- **`debugPrint` logları**: BLE ve biyometrik hatalar için `📶 [BLE]`, `📡 [BLE]`, `🔒 [Biyometrik]` prefix'li loglar var. `flutter run` çıktısında bunları arayarak diagnoze edilir.
- **Anahtar yönetimi**: Supabase URL ve anon key `.env` dosyasından `flutter_dotenv` ile yüklenir. `.env` git-ignore edilir (bkz. `.env.example`). Anon key zaten RLS ile kısıtlanmıştır. Release build'lerde R8 obfuscation (`isMinifyEnabled=true`) + `proguard-rules.pro` ile kod karıştırılır — `flutter build apk --obfuscate --split-debug-info=build/debug-info` kullanılır.

## Öğrenci verilerinin yerel cache'i

`shared_preferences` ile son kullanılan TC / Ad Soyad / NFC saklanır (`last_tc`, `last_name`, `last_nfc` — token saklanmaz, her oturumda değişir). Sayfa açılışında otomatik yüklenir + TC alanı focus alınca öneri rozeti gösterilir (`_applyTcSuggestion`). Kaydetme `_submit` başarılı olduğunda gerçekleşir (`_saveData`).

## Geliştirme

```powershell
# İlk kurulum: .env dosyasını oluştur (bkz. .env.example)
cp .env.example .env
# .env içindeki SUPABASE_URL ve SUPABASE_ANON_KEY değerlerini gerçek değerlerle doldur

flutter pub get
flutter analyze lib/main.dart          # uyarılar = withOpacity deprecation + curly braces, normal
flutter run --release                    # Telefona direkt yükle (tek ABI, ~15-18 MB)
flutter build apk --release --target-platform android-arm64   # Tek APK, modern telefonlar için
# Tüm mimariler + obfuscation:
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/debug-info
```

**Debug log izleme**: `flutter run` terminalde `📶 [BLE]`, `📡 [BLE]`, `🔒 [Biyometrik]` satırlarını gösterir. Native Kotlin logları için ayrıca `adb logcat | findstr YOKLAMA_BLE` (BLE advertise tarafında).

`pubspec.yaml` ana bağımlılıklar: `firebase_core`, `firebase_messaging`, `flutter_blue_plus` ^1.31, `local_auth`, `nfc_manager`, `supabase_flutter` (kullanılmıyor — REST direkt `http` ile), `shared_preferences`, `confetti`, `device_info_plus`.

## Sık yapılan değişiklikler

- **Akademisyen parolasını değiştir**: `_showAuth` içinde `"p"` string'inin iki kullanımı (l. ~312 ve ~327).
- **Tema rengi**: `YT.indigo` / `YT.green` vb. sabitleri (l. 44-49).
- **Supabase URL/key**: `.env` dosyasındaki `SUPABASE_URL` / `SUPABASE_ANON_KEY` değişkenleri. Değişiklikten sonra uygulamayı yeniden başlat.
- **BLE service UUID / manufacturer ID**: `kServiceUuid` / `kManufacturerId` (l. 23-24). Değiştirilirse hem `MainActivity.kt` advertiser tarafı hem dart scan tarafı senkron tutulmalı.
- **BLE tarama süreleri**: `_step3` içinde `_bleScanFiltered(12)` ve `_bleScanWide(8)` argümanları.
- **Oturum sayısı default**: `_selectedSessionCount = 1` (Teacher state).
- **Devamsızlık limiti**: `courses.absence_limit` (DB'den gelir), fallback `_courseType == 'uygulamali' ? 3 : 4`.
- **Biyometrik hata mesajı eklemek**: `_biometricErrorMsg` switch case'ine yeni `code` ekle.

## Test cihazları geçmişi

BLE tarama doğrulandı: Redmi Note 9 Pro, Redmi Note 11s, Xiaomi 13 (BLE 5.4, HyperOS).
Sorunlu olabilecek: Samsung A55 (BLE 5.3, Android 16), Redmi Note 12 5G (BLE 5.2) — filtreli tarama eklendikten sonra teorik olarak çalışmalı, henüz onaylanmadı.
