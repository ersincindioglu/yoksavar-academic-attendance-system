import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:confetti/confetti.dart';
import 'device_service.dart';

/* ============================
    AĞ VE KANAL YAPILANDIRMASI
============================ */
const String supabaseUrl = 'https://elddnvnrtsxcjoaxhocl.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVsZGRudm5ydHN4Y2pvYXhob2NsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc1NTM5NDYsImV4cCI6MjA4MzEyOTk0Nn0.E-5VcwWKURf7_VQq8K6T1HfKLK6UyldFx3ItywjMDsE';
const MethodChannel kNfcChannel = MethodChannel("yoklama/nfc");

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const YoklamaApp());
}

class YoklamaApp extends StatelessWidget {
  const YoklamaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6366F1),
      ),
      home: const RoleSelectPage(),
    );
  }
}

/* ============================
    MODERN ANA SAYFA
============================ */
class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.auto_awesome_motion_rounded,
              size: 80,
              color: Color(0xFF818CF8),
            ),
            const SizedBox(height: 20),
            const Text(
              "YOKSAVAR PRO",
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 60),
            _roleCard(
              context,
              "AKADEMİSYEN GİRİŞİ",
              Icons.account_balance_rounded,
              const Color(0xFF6366F1),
              () => _showAuth(context),
            ),
            const SizedBox(height: 20),
            _roleCard(
              context,
              "ÖĞRENCİ PORTALI",
              Icons.fingerprint_rounded,
              const Color(0xFF10B981),
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuth(BuildContext context) {
    final passCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Panel Güvenliği",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Şifre",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                if (passCtrl.text == "1234") {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherPage()),
                  );
                }
              },
              child: const Text("Giriş Yap"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
    VoidCallback tap,
  ) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 20),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================
    AKADEMİSYEN PANELİ
============================ */
class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});
  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  final hocaCtrl = TextEditingController(text: "Dr. Ersin");
  final dersCtrl = TextEditingController(text: "Mobil Programlama");
  String? sessionId;
  String? currentToken;
  bool isLive = false;

  String _genToken() => (100000 + (DateTime.now().millisecond * 7))
      .toString()
      .padLeft(6, '0')
      .substring(0, 6);

  Future<void> _startSession() async {
    final id =
        "DERS-${DateTime.now().millisecondsSinceEpoch.toString().substring(9)}";
    final staticToken = _genToken();

    final response = await http.post(
      Uri.parse("$supabaseUrl/rest/v1/sessions"),
      headers: {
        "Content-Type": "application/json",
        "apikey": supabaseAnonKey,
        "Authorization": "Bearer $supabaseAnonKey",
      },
      body: jsonEncode({
        "session_id": id,
        "teacher_name": hocaCtrl.text,
        "course_name": dersCtrl.text,
        "dynamic_token": staticToken,
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      setState(() {
        sessionId = id;
        currentToken = staticToken;
        isLive = true;
      });
      // Statik token - değişmiyor
    }
  }

  Future<void> _endSession() async {
    setState(() => isLive = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(title: const Text("Akademik Panel")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _inputCard(),
            if (isLive) ...[const SizedBox(height: 24), _liveCard()],
          ],
        ),
      ),
    );
  }

  Widget _inputCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: hocaCtrl,
            decoration: const InputDecoration(labelText: "Akademisyen"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: dersCtrl,
            decoration: const InputDecoration(labelText: "Ders Tanımı"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: isLive ? null : _startSession,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text("OTURUMU BAŞLAT"),
          ),
          if (isLive) const SizedBox(height: 10),
          if (isLive)
            ElevatedButton(
              onPressed: _endSession,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.red,
              ),
              child: const Text("OTURUMU KAPAT"),
            ),
        ],
      ),
    );
  }

  Widget _liveCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 20),
          const SizedBox(height: 10),
          const Text(
            "CANLI OTURUM",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "KOD: $sessionId",
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            currentToken ?? "...",
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "(Statik Token)",
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/* ============================
    ÖĞRENCİ PANELİ
============================ */
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
  bool s1 = false, s2 = false, s3 = false;
  String? nfcUid;
  String status = "İşlem bekliyor...";
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _step1() async {
    try {
      bool ok = await LocalAuthentication().authenticate(
        localizedReason: 'Biyometrik Kimlik Doğrulama',
      );
      if (ok && mounted)
        setState(() {
          s1 = true;
          status = "✅ Biyometrik doğrulandı.";
        });
    } catch (e) {
      if (mounted) setState(() => status = "⚠️ Biyometrik hata: $e");
    }
  }

  Future<void> _step2() async {
    try {
      final String? res = await kNfcChannel.invokeMethod<String>("scanUid");
      if (res != null && mounted)
        setState(() {
          nfcUid = res;
          s2 = true;
          status = "✅ Kart okundu: $res";
        });
    } catch (e) {
      if (mounted) setState(() => status = "⚠️ NFC hata: $e");
    }
  }

  Future<void> _step3() async {
    if (mounted) setState(() => status = "📡 Sınıf aranıyor...");
    bool found = false;

    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      var sub = FlutterBluePlus.onScanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.toUpperCase().contains("DERS") ||
              r.rssi > -55) {
            found = true;
            break;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 8));
      await sub.cancel();
      await FlutterBluePlus.stopScan();

      if (found && mounted) {
        setState(() {
          s3 = true;
          status = "✅ Konum doğrulandı.";
        });
      } else if (mounted) {
        setState(() => status = "❌ Hoca bulunamadı!");
      }
    } catch (e) {
      if (mounted) setState(() => status = "⚠️ BLE hata: $e");
    }
  }

  Future<void> _submit() async {
    if (mounted) setState(() => status = "⏳ Doğrulanıyor...");

    try {
      // Token kontrolü
      final res = await http.get(
        Uri.parse(
          "$supabaseUrl/rest/v1/sessions?session_id=eq.${sessionCtrl.text}",
        ),
        headers: {
          "apikey": supabaseAnonKey,
          "Authorization": "Bearer $supabaseAnonKey",
        },
      );

      print("🔍 DEBUG - Response Status: ${res.statusCode}");
      print("🔍 DEBUG - Response Body: ${res.body}");
      print("🔍 DEBUG - Aranan Session ID: ${sessionCtrl.text}");

      final data = jsonDecode(res.body);

      if (data.isEmpty) {
        if (mounted)
          setState(
            () => status = "❌ Oturum bulunamadı! Kod: ${sessionCtrl.text}",
          );
        return;
      }

      if (data[0]['dynamic_token'] != tokenCtrl.text) {
        if (mounted) setState(() => status = "❌ Hatalı Token!");
        return;
      }

      String? dUid = await DeviceService.getDeviceUID();

      // İLK GİREN KONTROLÜ - Mühürleme
      final attCheckRes = await http.get(
        Uri.parse(
          "$supabaseUrl/rest/v1/attendance?session_id=eq.${sessionCtrl.text}&select=student_id,device_uid",
        ),
        headers: {
          "apikey": supabaseAnonKey,
          "Authorization": "Bearer $supabaseAnonKey",
        },
      );

      final existingAtt = jsonDecode(attCheckRes.body);

      if (existingAtt.isNotEmpty) {
        // Zaten kayıt var - aynı TC ve cihaz mı kontrol et
        if (existingAtt[0]['student_id'] != tcCtrl.text ||
            existingAtt[0]['device_uid'] != dUid) {
          if (mounted)
            setState(
              () => status = "🔒 Bu oturuma başka bir öğrenci kaydoldu!",
            );
          return;
        }
      }

      // Yoklama kaydet
      final attRes = await http.post(
        Uri.parse("$supabaseUrl/rest/v1/attendance"),
        headers: {
          "Content-Type": "application/json",
          "apikey": supabaseAnonKey,
          "Authorization": "Bearer $supabaseAnonKey",
        },
        body: jsonEncode({
          "session_id": sessionCtrl.text,
          "student_id": tcCtrl.text,
          "full_name": nameCtrl.text,
          "device_uid": dUid,
          "nfc_uid": nfcUid ?? "NO_NFC",
        }),
      );

      if ((attRes.statusCode == 201 || attRes.statusCode == 200) && mounted) {
        _confetti.play();
        setState(() => status = "🎉 YOKLAMA BAŞARIYLA GÖNDERİLDİ! ✅");
      } else if (mounted) {
        setState(() => status = "❌ Kayıt hatası: ${attRes.statusCode}");
      }
    } catch (e) {
      if (mounted) setState(() => status = "⚠️ Bağlantı hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Öğrenci Portalı"),
        backgroundColor: const Color(0xFF10B981),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _formContainer(),
                const SizedBox(height: 24),
                _stepTile("1", "Biyometrik Onay", s1, _step1, true),
                const SizedBox(height: 10),
                _stepTile("2", "NFC Kart Doğrulama", s2, _step2, s1),
                const SizedBox(height: 10),
                _stepTile("3", "BLE Mesafe Onayı", s3, _step3, s2),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: (s1 && s2 && s3) ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: const Color(0xFF10B981),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text(
                    "YOKLAMAYI TAMAMLA",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formContainer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: sessionCtrl,
            decoration: const InputDecoration(
              labelText: "Oturum ID",
              prefixIcon: Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tcCtrl,
            decoration: const InputDecoration(
              labelText: "T.C. Kimlik",
              prefixIcon: Icon(Icons.badge),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: "Ad Soyad",
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: tokenCtrl,
            decoration: const InputDecoration(
              labelText: "Token",
              prefixIcon: Icon(Icons.pin),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _stepTile(String n, String t, bool ok, VoidCallback tap, bool en) {
    return Card(
      elevation: ok ? 3 : 1,
      color: ok ? Colors.green.shade50 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        enabled: en,
        leading: CircleAvatar(
          backgroundColor: ok ? Colors.green : Colors.grey.shade300,
          child: Text(
            n,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          t,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: ok ? Colors.green.shade900 : Colors.black87,
          ),
        ),
        trailing: Icon(
          ok ? Icons.check_circle : Icons.circle_outlined,
          color: ok ? Colors.green : Colors.grey,
        ),
        onTap: tap,
      ),
    );
  }
}
