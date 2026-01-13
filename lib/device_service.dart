import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  static Future<String?> getDeviceUID() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // Android ID kullan - cihaza özgü benzersiz kimlik
        return androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        // iOS için identifierForVendor kullan
        return iosInfo.identifierForVendor;
      }

      return "UNKNOWN_DEVICE";
    } catch (e) {
      print("Device UID hatası: $e");
      return "ERROR_${DateTime.now().millisecondsSinceEpoch}";
    }
  }
}
