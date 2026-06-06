🛡️ YOKSAVAR PRO
Çok Faktörlü Akademik Yoklama ve Güvenlik Ekosistemi

**YOKSAVAR PRO, eğitim kurumlarında geleneksel yoklama yöntemlerinin (manuel imza, sabit QR kod vb.) ötesine geçerek; biyometrik veriler, NFC teknolojisi ve Bluetooth Low Energy (BLE) yakınlık analizini harmanlayan üst düzey bir **Multi-Factor Authentication (MFA)** yoklama çözümüdür.

---

📋 Özet (Abstract)
Bu proje, yoklama süreçlerinde karşılaşılan "yerine imza atma" veya "uzaktan sahte bildirim" gibi suistimalleri fiziksel ve dijital doğrulamalarla engellemeyi amaçlar. Sistem; öğrencinin kimliğini, fiziksel cihaz sahipliğini ve konumunu akademik bir disiplin çerçevesinde doğrular.

---

🏗️ Uygulama Mimarisi (Architecture)
Sistem, Akademisyen ve Öğrenci panelleri arasında eş zamanlı ve asenkron bir veri akışı üzerine kuruludur.

<p align="center">
  <img src="https://github.com/user-attachments/assets/94ef54b3-db0d-4e76-96aa-6eea7fdcaa43" width="500" alt="Sistem Akış Şeması">
</p>



Doğrulama Katmanları:
1.  Biyometrik Katman:** `Local Authentication` protokolü ile cihaz düzeyinde parmak izi/yüz tanıma onayı.
2.  Donanım Mühürü (NFC):** Fiziksel öğrenci kimlik kartının UID (Unique Identifier) bilgisiyle materyal sahipliği doğrulaması.
3.  Yakınlık Analizi (BLE):** Hoca ve öğrenci cihazları arasındaki **RSSI** sinyal gücü verisiyle "sınıf içi fiziksel varlık" teyidi.
4.  Zaman Tabanlı Belirteç (Token):** Supabase üzerinden her 10 saniyede bir yenilenen dinamik şifre eşleşmesi.

---

## 📱 Uygulama Arayüzü

<table align="center">
  <tr>
    <td align="center"><b>Panel Güvenliği</b></td>
    <td align="center"><b>Akademik Panel</b></td>
    <td align="center"><b>Öğrenci Portalı</b></td>
  </tr>
  <tr>
    <td><img src="https://github.com/user-attachments/assets/3e145191-6ad7-4191-ab00-30a94c54b745" width="260"></td>
    <td><img src="https://github.com/user-attachments/assets/d9055760-f3dc-467f-84c2-b01b59923a26" width="260"></td>
    <td><img src="https://github.com/user-attachments/assets/ab348fe1-9bd4-443f-97a2-d77751dd3752" width="260"></td>
  </tr>
</table>

---

🛠️ Temel Teknolojiler ve Metodoloji
Biyometrik Güvenlik:** Kullanıcı doğrulaması cihazın güvenli bölgesinde (Secure Enclave) işlenir.
NFC Entegrasyonu:** Kart UID bilgileri, katılımın fiziksel kanıtı olarak veritabanına mühürlenir.
RSSI Optimizasyonu:** Hoca cihazı **Peripheral**, öğrenci cihazı **Central** olarak konumlanır; mesafe doğrulaması sinyal gücü eşikleriyle yapılır.
Real-time Senkronizasyon:** Dinamik tokenlar, **Supabase PostgREST** altyapısı ile milisaniyelik gecikmelerle hoca ve öğrenci arasında senkronize edilir.

---

## 📊 Veritabanı Yapısı (Database Schema)
Sistem, bulut tabanlı **Supabase (PostgreSQL)** mimarisi üzerinde kurgulanmıştır.
<p align="center">
  <img src="https://github.com/user-attachments/assets/21fb70be-6340-4211-8f3e-6679f2f11c71" width="500" alt="Veritabanı Şeması">
</p>

* **profiles:** Öğrenci kimlik, cihaz UID ve kart UID mühürleme bilgileri.
* **sessions:** Aktif ders oturumları ve anlık değişen dinamik token kayıtları.
* **attendance:** Başarıyla doğrulanmış kesin yoklama kayıtları.

---

## 🚀 Kurulum ve Çalıştırma

1.  Bağımlılıklar: Flutter SDK'nın sisteminizde yüklü olduğundan emin olun.
2.  Projeyi Klonlayın: `git clone https://github.com/ersincindioglu/yoksavar-pro.git`
3.  Paket Kurulumu: `flutter pub get`
4.  Konfigürasyon: Supabase `URL` ve `ANON_KEY` bilgilerinizi `main.dart` dosyasına ekleyin.
5.  Derleme: `flutter run` veya `flutter build apk --release`

---

📄 Lisans
Bu proje **MIT Lisansı** altında korunmaktadır. Akademik amaçlarla geliştirilmeye ve kullanıma açıktır.

**Geliştiren:** [Ersin CINDIOĞLU](https://github.com/ersincindioglu)c
