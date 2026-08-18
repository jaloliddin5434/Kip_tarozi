import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'api_exception.dart';

class ApiClient {
  /// Backend manzili. Dev uchun default — VPS/domen aniqlangach shu yerdan
  /// (yoki runtime sozlamadan) o'zgartiriladi.
  static String bazaUrl = 'http://localhost:8000/api/v1';

  /// Shu Flutter nusxasi qaysi jismoniy stansiyada ishlayotganini bildiradi
  /// (backenddagi `stansiyalar.id`). Har bir operator kompyuteri o'z build/
  /// konfiguratsiyasida boshqa qiymat bilan sozlanadi. Bitta stansiya bo'lsa — 1.
  static int? stansiyaId = 1;

  String? token;

  Map<String, String> _sarlavhalar([String? tokenOverride]) {
    final amaldagiToken = tokenOverride ?? token;
    return {
      'Content-Type': 'application/json',
      if (amaldagiToken != null) 'Authorization': 'Bearer $amaldagiToken',
    };
  }

  Uri _uri(String yol, [Map<String, dynamic>? query]) {
    final tozaQuery = query?.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse('$bazaUrl$yol').replace(queryParameters: tozaQuery);
  }

  Never _xatoTashla(http.Response javob) {
    dynamic tana;
    try {
      tana = jsonDecode(utf8.decode(javob.bodyBytes));
    } catch (_) {
      tana = null;
    }

    final detail = tana is Map ? tana['detail'] : null;
    String xabar;
    if (detail is String) {
      xabar = detail;
    } else if (detail is Map && detail['xabar'] != null) {
      xabar = detail['xabar'];
    } else if (detail is List) {
      xabar = detail.map((e) => e['msg'] ?? e.toString()).join(', ');
    } else {
      xabar = 'Server xatosi (${javob.statusCode})';
    }

    throw ApiException(javob.statusCode, xabar, tafsilot: detail);
  }

  dynamic _javobniQayta(http.Response javob) {
    if (javob.statusCode >= 200 && javob.statusCode < 300) {
      if (javob.body.isEmpty) return null;
      return jsonDecode(utf8.decode(javob.bodyBytes));
    }
    _xatoTashla(javob);
  }

  Future<dynamic> get(String yol, {Map<String, dynamic>? query, String? tokenOverride}) async {
    final javob = await http.get(_uri(yol, query), headers: _sarlavhalar(tokenOverride));
    return _javobniQayta(javob);
  }

  /// JSON emas, xom bayt oqimi qaytaradigan endpointlar uchun (masalan
  /// Excel/PDF fayl yuklab olish). Muvaffaqiyatsiz bo'lsa xuddi [get] kabi
  /// JSON xato xabarini o'qib [ApiException] otadi.
  Future<Uint8List> getBaytlar(String yol, {Map<String, dynamic>? query}) async {
    final javob = await http.get(_uri(yol, query), headers: _sarlavhalar());
    if (javob.statusCode >= 200 && javob.statusCode < 300) {
      return javob.bodyBytes;
    }
    _xatoTashla(javob);
  }

  Future<dynamic> post(String yol, {Map<String, dynamic>? tana}) async {
    final javob = await http.post(_uri(yol), headers: _sarlavhalar(), body: tana == null ? null : jsonEncode(tana));
    return _javobniQayta(javob);
  }

  Future<dynamic> patch(String yol, {Map<String, dynamic>? tana}) async {
    final javob = await http.patch(_uri(yol), headers: _sarlavhalar(), body: tana == null ? null : jsonEncode(tana));
    return _javobniQayta(javob);
  }

  Future<dynamic> put(String yol, {Map<String, dynamic>? tana}) async {
    final javob = await http.put(_uri(yol), headers: _sarlavhalar(), body: tana == null ? null : jsonEncode(tana));
    return _javobniQayta(javob);
  }

  Future<dynamic> delete(String yol, {Map<String, dynamic>? tana}) async {
    final sorov = http.Request('DELETE', _uri(yol))
      ..headers.addAll(_sarlavhalar())
      ..body = tana == null ? '' : jsonEncode(tana);
    final oqim = await sorov.send();
    final javob = await http.Response.fromStream(oqim);
    return _javobniQayta(javob);
  }
}
