import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:confetti/confetti.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'device_service.dart';

/* ============================
    AĞ VE KANAL YAPILANDIRMASI
============================ */
String supabaseUrl = '';
String supabaseAnonKey = '';
const MethodChannel kNfcChannel = MethodChannel("yoklama/nfc");
const MethodChannel kBleChannel = MethodChannel("yoklama/ble");
const String kServiceUuid = "0000abcd-0000-1000-8000-00805f9b34fb";
const int kManufacturerId = 0xFF01;

/* ═══════════════════════════════
   TEMA YÖNETİMİ
═══════════════════════════════ */
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class YT {
  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  // Arka planlar
  static Color bg(BuildContext c) => isDark(c) ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  static Color cardBg(BuildContext c) => isDark(c) ? Colors.white.withOpacity(0.04) : Colors.white;
  static Color cardBorder(BuildContext c) => isDark(c) ? Colors.white.withOpacity(0.06) : const Color(0xFFE2E8F0);
  // Metin
  static Color textPrimary(BuildContext c) => isDark(c) ? Colors.white : const Color(0xFF0F172A);
  static Color textSecondary(BuildContext c) => isDark(c) ? Colors.white.withOpacity(0.5) : const Color(0xFF64748B);
  static Color textMuted(BuildContext c) => isDark(c) ? Colors.white.withOpacity(0.3) : const Color(0xFF94A3B8);
  // Input
  static Color inputBg(BuildContext c) => isDark(c) ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC);
  // Sabit renkler
  static const indigo = Color(0xFF6366F1);
  static const indigoLight = Color(0xFF818CF8);
  static const green = Color(0xFF10B981);
  static const red = Color(0xFFEF4444);
  static const amber = Color(0xFFF59E0B);
  static const blue = Color(0xFF3B82F6);
}

bool isSupabaseOk(int code) => code == 200 || code == 201 || code == 204;

/* ═══════════════════════════════
   TEMA DEĞİŞTİR BUTONU
═══════════════════════════════ */
Widget themeToggleBtn(BuildContext c) {
  final dark = YT.isDark(c);
  return IconButton(
    onPressed: () => themeNotifier.value = dark ? ThemeMode.light : ThemeMode.dark,
    icon: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Icon(
        dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        key: ValueKey(dark),
        color: dark ? const Color(0xFFFBBF24) : YT.indigo,
      ),
    ),
    tooltip: dark ? "Açık Tema" : "Koyu Tema",
  );
}

/* ═══════════════════════════════
   BAŞLATMA
═══════════════════════════════ */
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env dosyasından anahtarları yükle
  try {
    await dotenv.load(fileName: ".env");
    supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  } catch (_) {
    // .env bulunamazsa varsayılan boş kalır
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Android bildirim kanalını native tarafta oluştur
  const platform = MethodChannel("yoklama/notifications");
  try { await platform.invokeMethod("createNotificationChannel"); } catch (_) {}

  runApp(const YoklamaApp());
}

class YoklamaApp extends StatelessWidget {
  const YoklamaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: FCMHelper.navigatorKey,
        themeMode: mode,
        // ══ AÇIK TEMA ══
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorSchemeSeed: YT.indigo,
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Color(0xFFF1F5F9),
            foregroundColor: Color(0xFF0F172A),
          ),
        ),
        // ══ KOYU TEMA ══
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: YT.indigo,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            backgroundColor: Color(0xFF0F172A),
            foregroundColor: Colors.white,
          ),
        ),
        home: const RoleSelectPage(),
      ),
    );
  }
}

/* ═══════════════════════════════
   FCM YARDIMCI
═══════════════════════════════ */
class FCMHelper {
  static Future<void> initFCM(String studentTcNo) async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null) { await _saveToken(studentTcNo, token); }
    messaging.onTokenRefresh.listen((t) => _saveToken(studentTcNo, t));

    // Ön plan bildirimi: Dialog + SnackBar
    FirebaseMessaging.onMessage.listen((msg) {
      if (msg.notification != null && _navigatorKey.currentContext != null) {
        final ctx = _navigatorKey.currentContext!;
        // Bildirim dialog'u göster
        showDialog(
          context: ctx,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              const Icon(Icons.notifications_active, color: YT.indigo, size: 24),
              const SizedBox(width: 10),
              Expanded(child: Text(msg.notification?.title ?? "Bildirim",
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ]),
            content: Text(msg.notification?.body ?? "", style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
                child: const Text("Tamam", style: TextStyle(color: YT.indigo, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      }
    });
  }

  static Future<void> _saveToken(String tc, String token) async {
    try {
      String? dUid = await DeviceService.getDeviceUID();
      await http.post(
        Uri.parse("$supabaseUrl/rest/v1/fcm_tokens?on_conflict=student_tc_no,device_uid"),
        headers: {
          "Content-Type": "application/json",
          "apikey": supabaseAnonKey,
          "Authorization": "Bearer $supabaseAnonKey",
          "Prefer": "resolution=merge-duplicates",
        },
        body: jsonEncode({
          "student_tc_no": tc,
          "device_uid": dUid ?? "unknown",
          "fcm_token": token,
          "updated_at": DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;
}

/* ═══════════════════════════════
   ANA SAYFA
═══════════════════════════════ */
class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = YT.isDark(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: dark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B), const Color(0xFF0F172A)]
                : [const Color(0xFFEEF2FF), const Color(0xFFF1F5F9), const Color(0xFFE0E7FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ═══ TEMA TOGGLE — Sağ üst ═══
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: themeToggleBtn(context),
                ),
              ),
              const Spacer(),
              // Logo
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: YT.indigoLight, width: 2),
                  boxShadow: [BoxShadow(color: YT.indigoLight.withOpacity(0.3), blurRadius: 30)],
                ),
                child: const Icon(Icons.auto_awesome_motion_rounded, size: 56, color: YT.indigoLight),
              ),
              const SizedBox(height: 24),
              Text("YOKSAVAR", style: TextStyle(
                fontSize: 36, fontWeight: FontWeight.w900,
                color: YT.textPrimary(context), letterSpacing: 4,
              )),
              const Text("PRO", style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: YT.indigoLight, letterSpacing: 8,
              )),
              const SizedBox(height: 8),
              Text("Akıllı Yoklama Sistemi", style: TextStyle(
                fontSize: 13, color: YT.textMuted(context), letterSpacing: 1,
              )),
              const SizedBox(height: 60),
              // Butonlar
              _roleBtn(context, "AKADEMİSYEN", Icons.school_rounded, YT.indigo, () => _showAuth(context)),
              const SizedBox(height: 16),
              _roleBtn(context, "ÖĞRENCİ", Icons.fingerprint_rounded, YT.green,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentPage()))),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  static void _showAuth(BuildContext context) {
    final passCtrl = TextEditingController();
    final dark = YT.isDark(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24, right: 24, top: 32,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: dark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(2),
          )),
          const SizedBox(height: 24),
          const Icon(Icons.lock_outline_rounded, color: YT.indigoLight, size: 40),
          const SizedBox(height: 12),
          Text("Panel Güvenliği", style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold,
            color: dark ? Colors.white : const Color(0xFF0F172A),
          )),
          const SizedBox(height: 24),
          TextField(
            controller: passCtrl, obscureText: true,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF0F172A),
              fontSize: 18, letterSpacing: 4,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: "• • • •",
              hintStyle: TextStyle(color: dark ? Colors.white.withOpacity(0.2) : Colors.black26),
              filled: true,
              fillColor: dark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: YT.indigo)),
            ),
            onSubmitted: (_) {
              if (passCtrl.text == "p") {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherPage()));
              }
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: YT.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                if (passCtrl.text == "p") {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherPage()));
                }
              },
              child: const Text("Giriş", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  static Widget _roleBtn(BuildContext context, String text, IconData icon, Color color, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.05)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 1)),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.5), size: 16),
        ]),
      ),
    );
  }
}

/* ═══════════════════════════════
   AKADEMİSYEN PANELİ
═══════════════════════════════ */
class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});
  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  // Ders listesi (Supabase'den çekilir)
  List<Map<String, dynamic>> _courses = [];
  String? _selectedCourseCode;
  bool _coursesLoading = true;

  // Seçili dersin bilgileri (otomatik dolar)
  String _courseName = "";
  String _courseType = "";
  String _teacherName = "";
  int _absenceLimit = 0;
  int _selectedSessionCount = 1;

  String? _activeSessionId, _activeToken;
  int _currentSessionNum = 0;
  bool _isLive = false, _isClosing = false, _isAdvertising = false;
  String _bleStatus = "";

  Timer? _pollTimer;
  final List<_AE> _recentAttendees = [];
  final Set<String> _seenStudentIds = {};
  List<Map<String, dynamic>> _todaySessions = [];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  /// Supabase'den dersleri yükle
  Future<void> _loadCourses() async {
    try {
      final r = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/courses?select=*&order=course_code.asc"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      if (r.statusCode == 200 && mounted) {
        final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
        setState(() { _courses = list; _coursesLoading = false; });
        // İlk dersi otomatik seç
        if (list.isNotEmpty) _selectCourse(list[0]['course_code']);
      }
    } catch (_) { if (mounted) setState(() => _coursesLoading = false); }
  }

  /// Ders seçildiğinde tüm bilgileri otomatik doldur
  void _selectCourse(String? code) {
    if (code == null) return;
    final course = _courses.firstWhere((c) => c['course_code'] == code, orElse: () => {});
    if (course.isEmpty) return;
    setState(() {
      _selectedCourseCode = code;
      _courseName = course['course_name'] ?? '';
      _courseType = course['course_type'] ?? 'teorik';
      _teacherName = course['teacher_name'] ?? '';
      _absenceLimit = course['absence_limit'] ?? (_courseType == 'uygulamali' ? 3 : 4);
      // Oturum sayısını DEĞİŞTİRME — hoca kendisi seçer
    });
    _loadTodaySessions();
  }

  Future<void> _loadTodaySessions() async {
    if (_courseName.isEmpty) return;
    try {
      final t = DateTime.now();
      final ts = "${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}T00:00:00";
      final r = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/sessions?course_name=eq.${Uri.encodeComponent(_courseName)}&created_at=gte.$ts&select=session_id,session_number,is_closed,created_at&order=created_at.asc"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      if (r.statusCode == 200 && mounted) {
        setState(() => _todaySessions = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  String _genToken() => ((DateTime.now().millisecondsSinceEpoch % 900000) + 100000).toString();

  Future<void> _startBle() async {
    try {
      final ok = await kBleChannel.invokeMethod<bool>("requestPermissions") ?? false;
      if (!ok) { setState(() => _bleStatus = "⚠️ BT izinleri reddedildi!"); return; }
      final s = await kBleChannel.invokeMethod<bool>("startAdvertising", {"name": _activeSessionId ?? "DERS"}) ?? false;
      setState(() {
        _isAdvertising = s;
        _bleStatus = s ? "📡 Sinyal: $_activeSessionId" : "⚠️ BLE başlatılamadı!";
      });
    } catch (e) {
      setState(() => _bleStatus = "⚠️ BLE Hata: $e");
    }
  }

  Future<void> _stopBle() async {
    try { await kBleChannel.invokeMethod("stopAdvertising"); setState(() { _isAdvertising = false; _bleStatus = ""; }); } catch (_) {}
  }

  void _startPolling() {
    _seenStudentIds.clear();
    _recentAttendees.clear();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchAttendance());
  }

  Future<void> _fetchAttendance() async {
    if (_activeSessionId == null) return;
    try {
      final r = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/attendance?session_id=eq.$_activeSessionId&select=student_id,full_name,created_at&order=created_at.desc"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      if (r.statusCode == 200) {
        for (var d in jsonDecode(r.body)) {
          final sid = d['student_id'] ?? '';
          if (!_seenStudentIds.contains(sid)) {
            _seenStudentIds.add(sid);
            final e = _AE(name: d['full_name'] ?? '?', studentId: sid, time: DateTime.now());
            if (mounted) setState(() => _recentAttendees.insert(0, e));
            Future.delayed(const Duration(seconds: 8), () { if (mounted) setState(() => _recentAttendees.remove(e)); });
          }
        }
      }
    } catch (_) {}
  }

  void _stopPolling() { _pollTimer?.cancel(); _pollTimer = null; }

  Future<void> _startSession() async {
    final id = "DERS-${DateTime.now().millisecondsSinceEpoch.toString().substring(9)}";
    final token = _genToken();
    final sNum = _todaySessions.length + 1;
    try {
      final r = await http.post(
        Uri.parse("$supabaseUrl/rest/v1/sessions"),
        headers: {
          "Content-Type": "application/json",
          "apikey": supabaseAnonKey,
          "Authorization": "Bearer $supabaseAnonKey",
          "Prefer": "return=minimal",
        },
        body: jsonEncode({
          "session_id": id,
          "teacher_name": _teacherName,
          "course_name": _courseName,
          "dynamic_token": token,
          "course_type": _courseType,
          "session_number": sNum,
          "total_sessions_per_week": _selectedSessionCount,
          "is_closed": false,
          "course_code": _selectedCourseCode,
        }),
      );
      if (isSupabaseOk(r.statusCode)) {
        setState(() { _activeSessionId = id; _activeToken = token; _currentSessionNum = sNum; _isLive = true; });
        await _startBle();
        _startPolling();
        await _loadTodaySessions();
      } else {
        _showErr("Oturum hatası: ${r.statusCode}\n${r.body}");
      }
    } catch (e) {
      _showErr("Bağlantı hatası: $e");
    }
  }

  Future<void> _endSession() async {
    if (_isClosing) return;
    setState(() => _isClosing = true);
    await _stopBle();
    _stopPolling();
    try {
      await http.patch(
        Uri.parse("$supabaseUrl/rest/v1/sessions?session_id=eq.$_activeSessionId"),
        headers: {"Content-Type": "application/json", "apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey", "Prefer": "return=minimal"},
        body: jsonEncode({"is_closed": true}),
      );
      await http.post(
        Uri.parse("$supabaseUrl/functions/v1/send-attendance-notification"),
        headers: {"Content-Type": "application/json", "apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
        body: jsonEncode({
          "session_id": _activeSessionId,
          "course_name": _courseName,
          "course_code": _selectedCourseCode,
          "course_type": _courseType,
          "teacher_name": _teacherName,
          "session_number": _currentSessionNum,
        }),
      );
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("✅ Oturum #$_currentSessionNum kapatıldı • ${_seenStudentIds.length} katılımcı"),
        backgroundColor: YT.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      setState(() { _isLive = false; _isClosing = false; _recentAttendees.clear(); _seenStudentIds.clear(); });
      _loadTodaySessions();
    }
  }

  void _showErr(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() { _stopPolling(); _stopBle(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YT.bg(context),
      appBar: AppBar(
        title: const Text("Akademik Panel", style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [themeToggleBtn(context)],
      ),
      body: _isLive ? _liveView(context) : _setupView(context),
    );
  }

  // ══════════ SETUP VIEW ══════════
  Widget _setupView(BuildContext c) {
    if (_coursesLoading) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: YT.indigo),
        SizedBox(height: 16),
        Text("Dersler yükleniyor...", style: TextStyle(color: Color(0xFF64748B))),
      ]));
    }
    if (_courses.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.school_outlined, size: 64, color: YT.textMuted(c)),
        const SizedBox(height: 16),
        Text("Henüz ders tanımlanmamış", style: TextStyle(color: YT.textMuted(c), fontSize: 16)),
        const SizedBox(height: 8),
        Text("Admin panelinden toplu import yapın", style: TextStyle(color: YT.textMuted(c), fontSize: 13)),
      ]));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ═══ DERS SEÇİMİ (DROPDOWN) ═══
        _card(c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec(c, "📚 Ders Seçimi"),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: YT.inputBg(c), borderRadius: BorderRadius.circular(14), border: Border.all(color: YT.cardBorder(c))),
            child: DropdownButton<String>(
              value: _selectedCourseCode,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: YT.textMuted(c)),
              dropdownColor: YT.isDark(c) ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(color: YT.textPrimary(c), fontSize: 15, fontWeight: FontWeight.w600),
              items: _courses.map((course) => DropdownMenuItem<String>(
                value: course['course_code'] as String,
                child: Text("${course['course_code']} — ${course['course_name']}"),
              )).toList(),
              onChanged: _isLive ? null : (v) => _selectCourse(v),
            ),
          ),
        ])),
        const SizedBox(height: 16),

        // ═══ OTOMATİK BİLGİLER (Salt okunur) ═══
        _card(c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec(c, "📋 Ders Bilgileri"),
          const SizedBox(height: 12),
          _infoRow(c, "Akademisyen", _teacherName, Icons.person_outline),
          const SizedBox(height: 8),
          // Ders Tipi — hoca manuel seçer (DB'deki değer default olur)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: YT.inputBg(c), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(_courseType == "uygulamali" ? Icons.computer_rounded : Icons.menu_book_rounded,
                  color: YT.textMuted(c), size: 18),
              const SizedBox(width: 12),
              Text("Ders Tipi", style: TextStyle(color: YT.textSecondary(c), fontSize: 13)),
              const Spacer(),
              DropdownButton<String>(
                value: _courseType == "uygulamali" ? "uygulamali" : "teorik",
                underline: const SizedBox(),
                isDense: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: YT.textMuted(c), size: 20),
                dropdownColor: YT.isDark(c) ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: YT.textPrimary(c), fontSize: 14, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: "teorik", child: Text("Teorik")),
                  DropdownMenuItem(value: "uygulamali", child: Text("Uygulamalı")),
                ],
                onChanged: _isLive ? null : (v) {
                  if (v == null) return;
                  setState(() {
                    _courseType = v;
                    _absenceLimit = v == "uygulamali" ? 3 : 4;
                  });
                },
              ),
            ]),
          ),
          const SizedBox(height: 8),
          _infoRow(c, "Devamsızlık Limiti", "$_absenceLimit hafta", Icons.warning_amber_rounded),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (_courseType == "uygulamali" ? YT.amber : YT.blue).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _courseType == "uygulamali"
                  ? "⚠️ Uygulamalı ders — Devamsızlık limiti: $_absenceLimit hafta"
                  : "ℹ️ Teorik ders — Devamsızlık limiti: $_absenceLimit hafta",
              style: TextStyle(fontSize: 12, color: _courseType == "uygulamali" ? YT.amber : YT.blue, fontWeight: FontWeight.w500),
            ),
          ),
        ])),
        const SizedBox(height: 16),

        // ═══ OTURUM SAYISI (Hoca seçer — her ders için farklı olabilir) ═══
        _card(c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sec(c, "🎯 Bugün Kaç Oturum?"),
          const SizedBox(height: 8),
          Text("Kağıt yoklamadaki imza sayısı gibi düşünün", style: TextStyle(color: YT.textSecondary(c), fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _sessionChip(c, 1)),
            const SizedBox(width: 8),
            Expanded(child: _sessionChip(c, 2)),
            const SizedBox(width: 8),
            Expanded(child: _sessionChip(c, 3)),
          ]),
        ])),
        const SizedBox(height: 16),

        // Bugünkü Oturumlar
        if (_todaySessions.isNotEmpty) ...[
          _card(c, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sec(c, "📅 Bugünkü Oturumlar"),
            const SizedBox(height: 12),
            ..._todaySessions.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (s['is_closed'] == true ? YT.green : YT.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(s['is_closed'] == true ? Icons.check_circle : Icons.circle,
                    color: s['is_closed'] == true ? YT.green : YT.red, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text("${s['session_number']}. Oturum — ${s['session_id']}",
                    style: TextStyle(color: YT.textPrimary(c).withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w500))),
                Text(s['is_closed'] == true ? "Kapalı" : "Aktif",
                    style: TextStyle(color: s['is_closed'] == true ? YT.green : YT.red, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            )),
          ])),
          const SizedBox(height: 16),
        ],

        // Başlat Butonu
        SizedBox(
          width: double.infinity, height: 56,
          child: ElevatedButton(
            onPressed: _todaySessions.length >= _selectedSessionCount ? null : _startSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: YT.indigo,
              disabledBackgroundColor: YT.textMuted(c).withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _todaySessions.length >= _selectedSessionCount
                ? Text("Bugünkü Oturumlar Tamamlandı", style: TextStyle(color: YT.textMuted(c), fontWeight: FontWeight.w600))
                : Text("OTURUMU BAŞLAT  (${_todaySessions.length + 1} / $_selectedSessionCount)",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  // ══════════ CANLI OTURUM VIEW ══════════
  Widget _liveView(BuildContext c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Kırmızı canlı kart
        Container(
          width: double.infinity, padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: YT.red.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
              const SizedBox(width: 8),
              const Text("CANLI OTURUM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 2)),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(
                "${_courseType == 'uygulamali' ? '💻 Uygulamalı' : '📖 Teorik'} • Oturum $_currentSessionNum/$_selectedSessionCount",
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            Text("$_activeSessionId", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
            const SizedBox(height: 8),
            Text(_activeToken ?? "...", style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 6)),
            const SizedBox(height: 4),
            Text("Token", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.people, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text("${_seenStudentIds.length} Katılımcı", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // BLE Durum
        _card(c, child: Row(children: [
          Icon(_isAdvertising ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: _isAdvertising ? YT.green : YT.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isAdvertising ? "BLE Yayını Aktif" : "BLE Yayını Kapalı",
                style: TextStyle(color: _isAdvertising ? YT.green : YT.amber, fontWeight: FontWeight.w600, fontSize: 14)),
            if (_bleStatus.isNotEmpty) Text(_bleStatus, style: TextStyle(color: YT.textMuted(c), fontSize: 12)),
          ])),
          if (!_isAdvertising && _isLive)
            IconButton(icon: const Icon(Icons.refresh, color: YT.amber), onPressed: _startBle),
        ])),
        const SizedBox(height: 12),

        // Katılımcılar
        ..._recentAttendees.map((e) => _attCard(e)),
        const SizedBox(height: 20),

        // Kapat Butonu
        SizedBox(
          width: double.infinity, height: 56,
          child: ElevatedButton(
            onPressed: _isClosing ? null : _endSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: YT.cardBg(c),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: YT.red, width: 1.5),
              ),
              elevation: 0,
            ),
            child: _isClosing
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: YT.red, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text("Bildirimler Gönderiliyor...", style: TextStyle(color: YT.red, fontWeight: FontWeight.w600)),
                  ])
                : const Text("OTURUMU KAPAT", style: TextStyle(color: YT.red, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  // ══════════ UI YARDIMCILARI ══════════
  Widget _card(BuildContext c, {required Widget child}) => Container(
    width: double.infinity, padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: YT.cardBg(c),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: YT.cardBorder(c)),
      boxShadow: YT.isDark(c) ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
    ),
    child: child,
  );

  Widget _sec(BuildContext c, String t) =>
      Text(t, style: TextStyle(color: YT.textPrimary(c), fontWeight: FontWeight.w700, fontSize: 16));

  Widget _infoRow(BuildContext c, String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: YT.inputBg(c), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Icon(icon, color: YT.textMuted(c), size: 18),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(color: YT.textSecondary(c), fontSize: 13)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(color: YT.textPrimary(c), fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    ]),
  );

  Widget _sessionChip(BuildContext c, int count) {
    final sel = _selectedSessionCount == count;
    return GestureDetector(
      onTap: _isLive ? null : () => setState(() => _selectedSessionCount = count),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: sel ? YT.indigo.withOpacity(0.15) : YT.inputBg(c),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? YT.indigo : YT.cardBorder(c), width: sel ? 1.5 : 1),
        ),
        child: Column(children: [
          Text("$count", style: TextStyle(color: sel ? YT.indigoLight : YT.textMuted(c), fontWeight: FontWeight.w900, fontSize: 24)),
          const SizedBox(height: 2),
          Text("Oturum", style: TextStyle(color: sel ? YT.indigoLight : YT.textMuted(c), fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _attCard(_AE e) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 500),
    builder: (c, v, ch) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: ch)),
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: YT.green.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        const CircleAvatar(radius: 18, backgroundColor: Colors.white24, child: Icon(Icons.person_add, color: Colors.white, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          Text("TC: ${e.studentId} • ${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ])),
        const Icon(Icons.check_circle, color: Colors.white, size: 24),
      ]),
    ),
  );
}

class _AE {
  final String name, studentId;
  final DateTime time;
  _AE({required this.name, required this.studentId, required this.time});
}

/* ═══════════════════════════════
   ÖĞRENCİ PANELİ
═══════════════════════════════ */
class StudentPage extends StatefulWidget {
  const StudentPage({super.key});
  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  final sessionCtrl = TextEditingController();
  final tcCtrl = TextEditingController();
  final tokenCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final nfcManualCtrl = TextEditingController();
  final _tcFocus = FocusNode();

  bool s1 = false, s2 = false, s3 = false;
  String? nfcUid, _foundBleName;
  String status = "İşlem bekliyor...";
  bool _fcmInit = false;
  bool _nfcManualMode = false; // NFC: okut mu yoksa manuel mi

  // BLE adapter (açık/kapalı) — teacher panelindeki gibi öğrenci panelinde de göster
  BluetoothAdapterState _bleAdapterState = BluetoothAdapterState.unknown;
  StreamSubscription<BluetoothAdapterState>? _bleStateSub;
  bool _bleScanning = false;
  int _bleSeenCount = 0; // tarama sırasında görülen toplam cihaz (debug)

  // Son kullanılan bilgiler (Token saklanmaz — her oturumda değişir)
  String _savedTc = '', _savedName = '', _savedNfc = '';

  // Info kutucuk toggle'ları
  bool _showSessionInfo = false, _showTokenInfo = false;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _tcFocus.addListener(() { if (mounted) setState(() {}); });
    // BLE adapter durumunu dinle — bluetooth açıldı/kapatıldı anında UI güncellensin
    _bleStateSub = FlutterBluePlus.adapterState.listen((s) {
      debugPrint("📶 [BLE] Adapter state: $s");
      if (mounted) setState(() => _bleAdapterState = s);
    });
  }

  @override
  void dispose() {
    _tcFocus.dispose();
    _bleStateSub?.cancel();
    super.dispose();
  }

  /// Kayıtlı bilgileri belleğe al — TC alanı focus alınca öneri olarak gösterilir
  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTc = prefs.getString('last_tc') ?? '';
    final savedName = prefs.getString('last_name') ?? '';
    final savedNfc = prefs.getString('last_nfc') ?? '';
    if (mounted) {
      setState(() {
        _savedTc = savedTc;
        _savedName = savedName;
        _savedNfc = savedNfc;
      });
    }
  }

  /// Bilgileri cihaza kaydet (Token kaydedilmez — her oturumda değişir)
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    if (tcCtrl.text.isNotEmpty) await prefs.setString('last_tc', tcCtrl.text);
    if (nameCtrl.text.isNotEmpty) await prefs.setString('last_name', nameCtrl.text);
    if (nfcUid != null && nfcUid!.isNotEmpty) await prefs.setString('last_nfc', nfcUid!);
  }

  /// TC önerisine dokunulunca form alanlarını doldur
  void _applyTcSuggestion() {
    setState(() {
      tcCtrl.text = _savedTc;
      if (_savedName.isNotEmpty) nameCtrl.text = _savedName;
      if (_savedNfc.isNotEmpty) nfcManualCtrl.text = _savedNfc;
    });
    _tcFocus.unfocus();
    _tryFCM();
  }

  void _tryFCM() {
    if (!_fcmInit && tcCtrl.text.length >= 11) {
      _fcmInit = true;
      FCMHelper.initFCM(tcCtrl.text);
    }
  }

  Future<void> _step1() async {
    try {
      final auth = LocalAuthentication();

      // Cihaz biyometrik veya ekran kilidi destekliyor mu?
      final supported = await auth.isDeviceSupported();
      if (!supported) {
        if (mounted) setState(() => status =
            "⚠️ Bu cihaz biyometrik doğrulamayı desteklemiyor.\nEkran kilidi (PIN/Desen/Şifre) ayarlı olmalı.");
        return;
      }

      final ok = await auth.authenticate(
        localizedReason: 'Yoklama için kimliğinizi doğrulayın',
      );
      if (ok && mounted) {
        setState(() { s1 = true; status = "✅ Biyometrik doğrulandı."; });
      } else if (mounted) {
        setState(() => status = "⚠️ Biyometrik doğrulama iptal edildi.");
      }
    } on LocalAuthException catch (e) {
      debugPrint("🔒 [Biyometrik] LocalAuthException code=${e.code.name}");
      if (mounted) setState(() => status = "⚠️ ${_biometricErrorMsg(e.code.name, null)}");
    } on PlatformException catch (e) {
      debugPrint("🔒 [Biyometrik] PlatformException code=${e.code} msg=${e.message}");
      if (mounted) setState(() => status = "⚠️ ${_biometricErrorMsg(e.code, e.message)}");
    } catch (e) {
      debugPrint("🔒 [Biyometrik] Beklenmeyen hata: $e");
      if (mounted) setState(() => status = "⚠️ Biyometrik hata: $e");
    }
  }

  /// PlatformException kodlarını kullanıcı dostu Türkçe açıklamalara çevirir.
  /// `not available + Security credentials not available` → ekran kilidi yok demek.
  String _biometricErrorMsg(String code, String? msg) {
    final m = (msg ?? '').toLowerCase();
    final credsMissing = m.contains('security credentials') ||
        m.contains('credential') ||
        m.contains('passcode');

    switch (code) {
      case 'NotAvailable':
      case 'not_available':
      case 'notAvailable':
        if (credsMissing) {
          return "Ekran kilidi ayarlı değil!\n"
              "Telefon Ayarları → Güvenlik → Ekran Kilidi'nden bir PIN/Desen/Şifre ekleyin, "
              "ardından parmak izini kaydedip tekrar deneyin.\n"
              "(Detay: $code — ${msg ?? '-'})";
        }
        return "Biyometrik doğrulama şu an kullanılamıyor. Ekran kilidi ve parmak izi ayarlarını kontrol edin.\n"
            "(Detay: $code — ${msg ?? '-'})";
      case 'NotEnrolled':
      case 'not_enrolled':
      case 'notEnrolled':
        return "Parmak izi kayıtlı değil!\n"
            "Telefon Ayarları → Güvenlik → Parmak İzi'nden parmak izinizi ekleyip tekrar deneyin.";
      case 'LockedOut':
      case 'lock_out':
      case 'locked_out':
      case 'lockedOut':
        return "Çok fazla hatalı deneme! 30 sn bekleyip tekrar deneyin.";
      case 'PermanentlyLockedOut':
      case 'permanent_lock_out':
      case 'permanently_locked_out':
      case 'permanentlyLockedOut':
        return "Biyometrik kilit kalıcı olarak devre dışı.\n"
            "Önce telefonun PIN/Şifresi ile kilidi açın, sonra tekrar deneyin.";
      case 'PasscodeNotSet':
      case 'passcode_not_set':
      case 'passcodeNotSet':
        return "Telefonda ekran kilidi (PIN/Şifre) tanımlı değil.\n"
            "Ayarlar → Güvenlik → Ekran Kilidi menüsünden ekleyin.";
      case 'OtherOperatingSystem':
      case 'biometricOnlyNotSupported':
        return "İşletim sistemi biyometrik doğrulamayı desteklemiyor.";
      case 'UserCanceled':
      case 'user_canceled':
      case 'userCanceled':
        return "Doğrulama iptal edildi.";
      default:
        return "Biyometrik hata ($code)\n${msg ?? '-'}\nLütfen ekran kilidini ve parmak izini kontrol edin.";
    }
  }

  /// NFC Adım 2: Okut veya Manuel Gir
  Future<void> _step2Scan() async {
    try {
      final r = await kNfcChannel.invokeMethod<String>("scanUid");
      if (r != null && r.isNotEmpty && mounted) {
        setState(() { nfcUid = r; nfcManualCtrl.text = r; s2 = true; status = "✅ Kart okundu: $r"; });
      } else if (mounted) {
        setState(() => status = "⚠️ Kart okunamadı. Manuel giriş yapabilirsiniz.");
      }
    } catch (e) {
      if (mounted) setState(() { status = "⚠️ NFC desteklenmiyor. Manuel giriş yapın."; _nfcManualMode = true; });
    }
  }

  void _step2Manual() {
    final val = nfcManualCtrl.text.trim();
    if (val.isNotEmpty && mounted) {
      setState(() { nfcUid = val; s2 = true; status = "✅ NFC manuel girildi: $val"; });
    } else if (mounted) {
      setState(() => status = "⚠️ NFC UID giriniz.");
    }
  }

  /// Bir tarama sonucundan "DERS-..." adını çıkarmaya çalışır.
  /// Üç farklı yolla bakar: manufacturer data → service UUID + manufacturer data → cihaz/advName.
  /// Bazı yeni Android cihazları (Samsung A55, MIUI vb.) sadece bazılarını yayınlıyor olabilir.
  String? _extractDersName(ScanResult r) {
    final mf = r.advertisementData.manufacturerData;
    // 1) Doğrudan manufacturer data (DERS-...)
    if (mf.containsKey(kManufacturerId)) {
      final d = utf8.decode(mf[kManufacturerId]!, allowMalformed: true);
      if (d.startsWith("DERS-")) return d;
    }
    // 2) Service UUID eşleşmesi → manufacturer datayı oku (farklı ID ile yayılmış olabilir)
    for (final u in r.advertisementData.serviceUuids.map((e) => e.toString().toLowerCase())) {
      if (u == kServiceUuid) {
        for (final e in mf.entries) {
          final d = utf8.decode(e.value, allowMalformed: true);
          if (d.startsWith("DERS-")) return d;
        }
      }
    }
    // 3) Cihaz/advertised adı (scan response'tan)
    final pN = r.device.platformName;
    final aN = r.advertisementData.advName;
    if (pN.toUpperCase().startsWith("DERS-")) return pN;
    if (aN.toUpperCase().startsWith("DERS-")) return aN;
    return null;
  }

  /// UUID filtreli tarama — KRİTİK:
  /// Android 12+ (API 31+) — Samsung A55, Redmi Note 12/MIUI, vb. — `withServices`
  /// filtresi yoksa OS tarafından scan throttling uygulanıyor. Filtreli tarama donanım
  /// seviyesinde filtreleme yaptığı için bu throttling'e tabi DEĞİL ve çok daha güvenilir.
  Future<String?> _bleScanFiltered(int seconds) async {
    String? result;
    StreamSubscription? sub;
    final done = Completer<void>();
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300));
      debugPrint("📡 [BLE] Filtreli tarama başlıyor (UUID=$kServiceUuid, ${seconds}s)");
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: [Guid(kServiceUuid)],
        timeout: Duration(seconds: seconds + 2),
      );
      sub = FlutterBluePlus.onScanResults.listen((results) {
        if (done.isCompleted) return;
        for (final r in results) {
          _bleSeenCount = results.length;
          final name = _extractDersName(r);
          if (name != null) {
            debugPrint("✅ [BLE] Filtreli tarama buldu: $name (rssi=${r.rssi})");
            result = name;
            if (!done.isCompleted) done.complete();
            return;
          }
        }
      });
      await Future.any([done.future, Future.delayed(Duration(seconds: seconds))]);
    } catch (e) {
      debugPrint("⚠️ [BLE] Filtreli tarama hatası: $e");
    } finally {
      await sub?.cancel();
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
    }
    return result;
  }

  /// Filtresiz geniş tarama — yedek.
  /// Eski/uyumsuz cihazlarda UUID filtresi yanlış çalışabilir; bu sefer her cihaz
  /// taranıp manufacturer/ad alanı manuel kontrol edilir.
  Future<String?> _bleScanWide(int seconds) async {
    String? result;
    StreamSubscription? sub;
    final done = Completer<void>();
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      debugPrint("📡 [BLE] Geniş tarama başlıyor (filtresiz, ${seconds}s)");
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        timeout: Duration(seconds: seconds + 2),
      );
      sub = FlutterBluePlus.onScanResults.listen((results) {
        if (done.isCompleted) return;
        _bleSeenCount = results.length;
        for (final r in results) {
          final name = _extractDersName(r);
          if (name != null) {
            debugPrint("✅ [BLE] Geniş tarama buldu: $name (rssi=${r.rssi})");
            result = name;
            if (!done.isCompleted) done.complete();
            return;
          }
        }
      });
      await Future.any([done.future, Future.delayed(Duration(seconds: seconds))]);
    } catch (e) {
      debugPrint("⚠️ [BLE] Geniş tarama hatası: $e");
    } finally {
      await sub?.cancel();
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
    }
    return result;
  }

  Future<void> _step3() async {
    // 1) BLE açık mı kontrol et — kapalıysa kullanıcıya açık talimat ver
    if (_bleAdapterState != BluetoothAdapterState.on) {
      if (mounted) {
        setState(() => status = _bleAdapterState == BluetoothAdapterState.off
            ? "⚠️ Bluetooth KAPALI!\nLütfen telefonun bildirim panelinden veya Ayarlar'dan Bluetooth'u açın, sonra tekrar deneyin."
            : "⚠️ Bluetooth durumu belirsiz ($_bleAdapterState). Bluetooth'u kapatıp açın.");
      }
      return;
    }

    if (mounted) {
      setState(() {
        _bleScanning = true;
        _bleSeenCount = 0;
        status = "📡 Sınıf sinyali aranıyor (filtreli mod, ~12 sn)...";
      });
    }

    // 2) Önce UUID filtreli tarama (Android 12+/yeni telefonlar için kritik)
    String? fId = await _bleScanFiltered(12);

    // 3) Bulunamazsa filtresiz geniş tarama (uyumsuzluk yedeği)
    if (fId == null) {
      if (mounted) setState(() => status =
          "📡 Filtreli tarama bulamadı, geniş tarama (~8 sn)... [Görülen cihaz: $_bleSeenCount]");
      fId = await _bleScanWide(8);
    }

    if (mounted) setState(() => _bleScanning = false);

    if (fId != null && mounted) {
      _foundBleName = fId;
      sessionCtrl.text = fId;
      setState(() { s3 = true; status = "✅ Sınıf bulundu: $fId"; });
    } else if (mounted) {
      setState(() => status =
          "❌ Sınıf sinyali bulunamadı!\n"
          "• Öğretmen oturumu başlattı mı?\n"
          "• Sınıfa yeterince yakın mısınız (~10 m)?\n"
          "• Bluetooth açık mı? Konum servisi açık mı?\n"
          "• Çevrede görülen toplam BLE cihaz: $_bleSeenCount");
    }
  }

  Future<void> _submit() async {
    _tryFCM();
    if (mounted) setState(() => status = "⏳ Doğrulanıyor...");
    try {
      // 1. Oturum + Token doğrula
      final r = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/sessions?session_id=eq.${sessionCtrl.text}"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      final data = jsonDecode(r.body);
      if (data.isEmpty) { if (mounted) setState(() => status = "❌ Oturum bulunamadı!"); return; }
      if (data[0]['dynamic_token'] != tokenCtrl.text) { if (mounted) setState(() => status = "❌ Hatalı Token!"); return; }

      final sessionCourseCode = data[0]['course_code'] ?? '';

      // 2. ENROLLMENT KONTROLÜ — Bu TC bu derse kayıtlı mı?
      final enrollRes = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/enrollments?student_tc_no=eq.${tcCtrl.text}&course_code=eq.$sessionCourseCode&select=student_tc_no,full_name"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      final enrollData = jsonDecode(enrollRes.body);
      if (enrollData.isEmpty) {
        if (mounted) setState(() => status = "❌ Bu TC (${ tcCtrl.text}) bu derse ($sessionCourseCode) kayıtlı değil!\nAdmin panelinden kayıt yapılmalıdır.");
        return;
      }

      // Ad soyad otomatik doldur (enrollment'tan)
      final enrolledName = enrollData[0]['full_name'] ?? nameCtrl.text;
      if (nameCtrl.text.isEmpty) nameCtrl.text = enrolledName;

      String? dUid = await DeviceService.getDeviceUID();

      // 3. MÜHÜRLEME — profiles kontrolü
      final pr = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/profiles?student_tc_no=eq.${tcCtrl.text}"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      final pd = jsonDecode(pr.body);

      if (pd.isEmpty) {
        // İlk kullanım → mühürle (cihaz eklenir, NFC zaten import'ta mühürlenmişse güncelleme yapar)
        await http.post(
          Uri.parse("$supabaseUrl/rest/v1/profiles?on_conflict=student_tc_no"),
          headers: {"Content-Type": "application/json", "apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey", "Prefer": "resolution=merge-duplicates,return=minimal"},
          body: jsonEncode({
            "student_tc_no": tcCtrl.text,
            "full_name": enrolledName,
            "registered_device_uid": dUid,
            "registered_nfc_uid": nfcUid ?? "NO_NFC",
            "is_registered": true,
          }),
        );
      } else {
        final p = pd[0];
        // Cihaz kontrolü
        if (p['registered_device_uid'] != null && p['registered_device_uid'] != dUid) {
          if (mounted) setState(() => status = "🔒 Bu TC farklı bir cihaza mühürlü!\nCihaz değişikliği için admin ile iletişime geçin.");
          return;
        }
        // Cihaz henüz mühürlenmemişse (import'ta sadece NFC eklenmiştir) → şimdi mühürle
        if (p['registered_device_uid'] == null && dUid != null) {
          await http.patch(
            Uri.parse("$supabaseUrl/rest/v1/profiles?student_tc_no=eq.${tcCtrl.text}"),
            headers: {"Content-Type": "application/json", "apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey", "Prefer": "return=minimal"},
            body: jsonEncode({"registered_device_uid": dUid}),
          );
        }
        // NFC kontrolü
        if (p['registered_nfc_uid'] != null && p['registered_nfc_uid'] != "NO_NFC" && nfcUid != null && p['registered_nfc_uid'] != nfcUid) {
          if (mounted) setState(() => status = "🔒 NFC kartınız sistemdeki kayıtla uyuşmuyor!\nKayıtlı kart: ${p['registered_nfc_uid']}\nOkutulan kart: $nfcUid");
          return;
        }
      }

      // 4. Mükerrer kontrol
      final chk = await http.get(
        Uri.parse("$supabaseUrl/rest/v1/attendance?session_id=eq.${sessionCtrl.text}&student_id=eq.${tcCtrl.text}"),
        headers: {"apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey"},
      );
      if ((jsonDecode(chk.body) as List).isNotEmpty) {
        if (mounted) setState(() => status = "ℹ️ Bu oturuma zaten katılım sağladınız.");
        return;
      }

      // 5. Yoklama kaydet
      final att = await http.post(
        Uri.parse("$supabaseUrl/rest/v1/attendance"),
        headers: {"Content-Type": "application/json", "apikey": supabaseAnonKey, "Authorization": "Bearer $supabaseAnonKey", "Prefer": "return=minimal"},
        body: jsonEncode({
          "session_id": sessionCtrl.text,
          "student_id": tcCtrl.text,
          "full_name": enrolledName,
          "device_uid": dUid,
          "nfc_uid": nfcUid ?? "NO_NFC",
        }),
      );
      if (isSupabaseOk(att.statusCode) && mounted) {
        await _saveData(); // Bilgileri cihaza kaydet
        // Başarı ekranına geç — konfeti orada patlasın, sonra ana ekrana dön
        Navigator.of(context).pushReplacement(_fadeRoute(SuccessPage(studentName: enrolledName)));
      } else if (mounted) {
        setState(() => status = "❌ Kayıt hatası: ${att.statusCode}");
      }
    } catch (e) { if (mounted) setState(() => status = "⚠️ Bağlantı hatası: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    final c = context;
    return Scaffold(
      backgroundColor: YT.bg(c),
      appBar: AppBar(
        title: const Text("Öğrenci Portalı", style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: YT.green,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [themeToggleBtn(c)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
            // Form
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: YT.cardBg(c),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: YT.cardBorder(c)),
                boxShadow: YT.isDark(c) ? [] : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
              ),
              child: Column(children: [
                _sField(c, sessionCtrl, "Oturum ID", Icons.key,
                    suffix: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_foundBleName != null)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.bluetooth_connected, color: YT.green, size: 20),
                        ),
                      _helpBtn(c, () => setState(() => _showSessionInfo = !_showSessionInfo), active: _showSessionInfo),
                    ])),
                _infoBox(c,
                    visible: _showSessionInfo,
                    icon: Icons.bluetooth_searching_rounded,
                    text: "Bluetooth ile sınıf sinyaline bağlanıldığında bu alan otomatik dolar."),
                const SizedBox(height: 10),
                _sField(c, tcCtrl, "T.C. Kimlik No (11 hane)", Icons.badge,
                    keyboard: TextInputType.number, onChanged: (_) => _tryFCM(), focusNode: _tcFocus),
                // TC alanı focus aldığında, kayıtlı TC öneri olarak görünür
                if (_tcFocus.hasFocus && tcCtrl.text.isEmpty && _savedTc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: _applyTcSuggestion,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: YT.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: YT.indigo.withOpacity(0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.history_rounded, size: 16, color: YT.indigo),
                          const SizedBox(width: 6),
                          Text(_savedTc, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: YT.indigo)),
                        ]),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _sField(c, nameCtrl, "Ad Soyad", Icons.person),
                const SizedBox(height: 10),
                _sField(c, tokenCtrl, "Token", Icons.pin,
                    keyboard: TextInputType.number,
                    suffix: _helpBtn(c, () => setState(() => _showTokenInfo = !_showTokenInfo), active: _showTokenInfo)),
                _infoBox(c,
                    visible: _showTokenInfo,
                    icon: Icons.school_rounded,
                    text: "Token, akademisyen tarafından oturum başında sınıfta paylaşılır. Her oturumda değişir."),
              ]),
            ),
            const SizedBox(height: 20),

            // Adımlar
            _stepCard(c, "1", "Biyometrik Onay", s1, _step1, true),
            const SizedBox(height: 8),

            // ═══ NFC ADIMI — Okut veya Manuel ═══
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: s2 ? YT.green.withOpacity(0.1) : YT.cardBg(c),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: s2 ? YT.green.withOpacity(0.3) : YT.cardBorder(c)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 16, backgroundColor: s2 ? YT.green : s1 ? YT.textMuted(c).withOpacity(0.3) : YT.textMuted(c).withOpacity(0.1),
                    child: const Text("2", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13))),
                  const SizedBox(width: 14),
                  Expanded(child: Text("NFC Kart Doğrulama", style: TextStyle(fontWeight: FontWeight.w600, color: s2 ? YT.green : YT.textPrimary(c).withOpacity(0.7), fontSize: 14))),
                  Icon(s2 ? Icons.check_circle : Icons.circle_outlined, color: s2 ? YT.green : YT.textMuted(c).withOpacity(0.4), size: 22),
                ]),
                if (s1 && !s2) ...[
                  const SizedBox(height: 12),
                  // Okut / Manuel seçimi
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _nfcManualMode = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_nfcManualMode ? YT.indigo.withOpacity(0.15) : YT.inputBg(c),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: !_nfcManualMode ? YT.indigo : YT.cardBorder(c)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.contactless_rounded, size: 18, color: !_nfcManualMode ? YT.indigo : YT.textMuted(c)),
                          const SizedBox(width: 6),
                          Text("Okut", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: !_nfcManualMode ? YT.indigo : YT.textMuted(c))),
                        ]),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() => _nfcManualMode = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _nfcManualMode ? YT.amber.withOpacity(0.15) : YT.inputBg(c),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _nfcManualMode ? YT.amber : YT.cardBorder(c)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.edit_rounded, size: 18, color: _nfcManualMode ? YT.amber : YT.textMuted(c)),
                          const SizedBox(width: 6),
                          Text("Manuel", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _nfcManualMode ? YT.amber : YT.textMuted(c))),
                        ]),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 10),
                  if (_nfcManualMode) ...[
                    // Manuel NFC girişi
                    TextField(
                      controller: nfcManualCtrl,
                      style: TextStyle(color: YT.textPrimary(c), fontSize: 14, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: "NFC UID (örn: 04:A2:B1:C3)",
                        hintStyle: TextStyle(color: YT.textMuted(c), fontSize: 12),
                        filled: true, fillColor: YT.inputBg(c),
                        prefixIcon: Icon(Icons.nfc_rounded, color: YT.textMuted(c), size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, height: 40, child: ElevatedButton(
                      onPressed: _step2Manual,
                      style: ElevatedButton.styleFrom(backgroundColor: YT.amber, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text("Onayla", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    )),
                  ] else ...[
                    // NFC okutma butonu
                    SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(
                      onPressed: _step2Scan,
                      icon: const Icon(Icons.contactless_rounded, size: 18),
                      label: const Text("Kartı Okut", style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(backgroundColor: YT.indigo, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    )),
                  ],
                ],
              ]),
            ),
            const SizedBox(height: 8),

            // ═══ BLE Durum Göstergesi ═══ (BLE butonunun üstünde)
            _bleStatusBadge(c),
            const SizedBox(height: 6),
            _stepCard(c, "3", "BLE Mesafe Onayı", s3, _step3, s2),
            const SizedBox(height: 24),

            // Gönder
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: (s1 && s2 && s3) ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YT.green,
                  disabledBackgroundColor: YT.textMuted(c).withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("YOKLAMAYI TAMAMLA",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),

            // Durum
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: YT.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: YT.blue.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: YT.blue, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(status,
                    style: TextStyle(fontWeight: FontWeight.w600,
                        color: YT.isDark(c) ? const Color(0xFF93C5FD) : YT.blue, fontSize: 13))),
              ]),
            ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  /// Form alanı yanında '?' yardım butonu (aktifken indigo dolu, pasifken outline)
  Widget _helpBtn(BuildContext c, VoidCallback onTap, {required bool active}) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          active ? Icons.help_rounded : Icons.help_outline_rounded,
          color: active ? YT.indigo : YT.textMuted(c),
          size: 22,
        ),
      ),
    );
  }

  /// '?' tıklanınca açılan animasyonlu bilgi kutucuğu — uygulama temasına uyumlu
  Widget _infoBox(BuildContext c, {required bool visible, required IconData icon, required String text}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: visible
            ? Padding(
                key: const ValueKey('info-visible'),
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: YT.indigo.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: YT.indigo.withOpacity(0.3)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, color: YT.indigo, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text,
                          style: TextStyle(
                              color: YT.isDark(c) ? const Color(0xFFC7D2FE) : YT.indigo,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.3)),
                    ),
                  ]),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('info-hidden')),
      ),
    );
  }

  Widget _sField(BuildContext c, TextEditingController ctrl, String label, IconData icon,
      {Widget? suffix, TextInputType? keyboard, Function(String)? onChanged, FocusNode? focusNode}) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      keyboardType: keyboard,
      onChanged: onChanged,
      style: TextStyle(color: YT.textPrimary(c), fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: YT.textMuted(c), fontSize: 13),
        prefixIcon: Icon(icon, color: YT.textMuted(c), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: YT.inputBg(c),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: YT.green)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _stepCard(BuildContext c, String n, String t, bool ok, VoidCallback tap, bool en) {
    return GestureDetector(
      onTap: en ? tap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: ok ? YT.green.withOpacity(0.1) : YT.cardBg(c),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ok ? YT.green.withOpacity(0.3) : YT.cardBorder(c)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: ok ? YT.green : en ? YT.textMuted(c).withOpacity(0.3) : YT.textMuted(c).withOpacity(0.1),
            child: Text(n, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ok ? Colors.white : en ? YT.textSecondary(c) : YT.textMuted(c),
              fontSize: 13,
            )),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(t, style: TextStyle(
            fontWeight: FontWeight.w600,
            color: ok ? YT.green : en ? YT.textPrimary(c).withOpacity(0.7) : YT.textMuted(c),
            fontSize: 14,
          ))),
          Icon(ok ? Icons.check_circle : Icons.circle_outlined,
              color: ok ? YT.green : YT.textMuted(c).withOpacity(0.4), size: 22),
        ]),
      ),
    );
  }

  /// BLE açık/kapalı + tarama göstergesi — Teacher panelindeki gibi öğrenci tarafında da gösterir.
  /// BLE butonunun hemen üzerinde küçük bir rozet olarak görünür.
  Widget _bleStatusBadge(BuildContext c) {
    final bleOn = _bleAdapterState == BluetoothAdapterState.on;
    final bleOff = _bleAdapterState == BluetoothAdapterState.off;
    final Color clr = bleOn ? YT.green : (bleOff ? YT.red : YT.amber);
    final IconData ic = bleOn
        ? Icons.bluetooth_rounded
        : (bleOff ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_searching_rounded);
    final String label = bleOn
        ? (_bleScanning ? "Bluetooth Açık • Taranıyor..." : "Bluetooth Açık")
        : (bleOff ? "Bluetooth KAPALI — Açın!" : "Bluetooth Durumu: Bilinmiyor");

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: clr.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: clr.withOpacity(0.35)),
      ),
      child: Row(children: [
        Icon(ic, color: clr, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: clr, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        if (_bleScanning)
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: clr),
          ),
      ]),
    );
  }
}

/* ═══════════════════════════════
   SAYFA GEÇİŞİ — temaya uyumlu fade transition
═══════════════════════════════ */
PageRouteBuilder<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/* ═══════════════════════════════
   BAŞARI EKRANI — yoklama tamamlandıktan sonra
═══════════════════════════════ */
class SuccessPage extends StatefulWidget {
  final String studentName;
  const SuccessPage({super.key, required this.studentName});
  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage> with TickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confetti.play();
      _scaleCtrl.forward();
    });
    // 3.5 sn sonra ana ekrana fade ile dön
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        _fadeRoute(const RoleSelectPage()),
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context;
    return Scaffold(
      backgroundColor: YT.bg(c),
      body: Stack(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: YT.green.withOpacity(0.15),
                    border: Border.all(color: YT.green.withOpacity(0.4), width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, color: YT.green, size: 90),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                "Yoklama Tamamlandı!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: YT.textPrimary(c),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.studentName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: YT.green,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Katılımınız başarıyla kaydedildi.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: YT.textSecondary(c)),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: YT.indigo.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: YT.indigo.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(YT.indigo),
                      backgroundColor: YT.indigo.withOpacity(0.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Ana ekrana yönlendiriliyorsunuz…",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: YT.isDark(c) ? const Color(0xFFC7D2FE) : YT.indigo,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 30,
            maxBlastForce: 22,
            minBlastForce: 8,
            emissionFrequency: 0.05,
            gravity: 0.25,
            colors: const [YT.green, YT.indigo, YT.indigoLight, YT.amber, YT.blue],
          ),
        ),
      ]),
    );
  }
}