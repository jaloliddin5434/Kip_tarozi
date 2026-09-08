import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Operator kompyuteridagi Stansiya Agenti (localhost) orqali LAN kamerasidan
/// bitta JPEG kadr oladi. Manzil backend'ning `GET /kiplar/kamera-sozlamalari`
/// endpointidan olinadi (u faqat MANZILNI beradi — kamera login/parol emas;
/// Digest autentifikatsiya agent ichida).
///
/// Xatolik / kamera o'chiq / 204 -> null (kip suratsiz navbatga tushadi).
Future<Uint8List?> agentdanSurat(String agentSuratUrl) async {
  try {
    final javob = await http.get(Uri.parse(agentSuratUrl)).timeout(const Duration(seconds: 5));
    if (javob.statusCode == 200 && javob.bodyBytes.isNotEmpty) {
      return javob.bodyBytes;
    }
    return null;
  } catch (_) {
    return null;
  }
}
