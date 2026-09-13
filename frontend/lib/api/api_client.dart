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

  /// AUDIT TUZATISHI: markazlashgan "sessiya tugadi" signali — istisnosiz
  /// BARCHA so'rovlardan (oddiy chaqiruv, offline-navbat sinxroni, kamera-tasdiq
  /// poll va h.k.) 401 kelsa shu chaqiriladi (`sessiyaTekshiruvi: false` bilan
  /// yuborilgan alohida so'rovlar bundan mustasno — pastga qarang). `AppState`
  /// buni o'rnatib, global logout + login ekraniga qaytarishni bajaradi.
  void Function()? bir401SodirBoldi;

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

  dynamic _javobniQayta(http.Response javob, {bool sessiyaTekshiruvi = true}) {
    if (javob.statusCode >= 200 && javob.statusCode < 300) {
      if (javob.body.isEmpty) return null;
      return jsonDecode(utf8.decode(javob.bodyBytes));
    }
    // AUDIT TUZATISHI: 401 kelsa (va shu so'rov uchun sessiya-tekshiruvi
    // o'chirilmagan bo'lsa) — global "sessiya tugadi" signalini ishga
    // tushiramiz, SO'NG odatdagidek ApiException otamiz (chaqiruvchi
    // ekranning o'z xato-ko'rsatish mantig'i o'zgarmasdan davom etadi).
    if (javob.statusCode == 401 && sessiyaTekshiruvi) {
      bir401SodirBoldi?.call();
    }
    _xatoTashla(javob);
  }

  Future<dynamic> get(
    String yol, {
    Map<String, dynamic>? query,
    String? tokenOverride,
    bool sessiyaTekshiruvi = true,
  }) async {
    final javob = await http.get(_uri(yol, query), headers: _sarlavhalar(tokenOverride));
    return _javobniQayta(javob, sessiyaTekshiruvi: sessiyaTekshiruvi);
  }

  /// JSON emas, xom bayt oqimi qaytaradigan endpointlar uchun (masalan
  /// Excel/PDF fayl yuklab olish). Muvaffaqiyatsiz bo'lsa xuddi [get] kabi
  /// JSON xato xabarini o'qib [ApiException] otadi.
  Future<Uint8List> getBaytlar(String yol, {Map<String, dynamic>? query}) async {
    final javob = await http.get(_uri(yol, query), headers: _sarlavhalar());
    if (javob.statusCode >= 200 && javob.statusCode < 300) {
      return javob.bodyBytes;
    }
    if (javob.statusCode == 401) bir401SodirBoldi?.call();
    _xatoTashla(javob);
  }

  /// [tana] Map yoki List (JSON-kodlanadigan har qanday qiymat) bo'lishi mumkin —
  /// masalan `/kiplar/sinxron` ro'yxat qabul qiladi. [tokenOverride] berilsa,
  /// joriy sessiya tokeni o'rniga o'sha ishlatiladi (offline navbatni saqlagan
  /// operator tokeni bilan yuborish uchun). [sessiyaTekshiruvi] `false` bo'lsa,
  /// 401 kelganda global logout ISHGA TUSHMAYDI — faqat 401'ning o'zi boshqa
  /// (sessiya tugashidan farqli) ma'noni anglatadigan endpointlar uchun,
  /// masalan `/moliyaviy/kirish` (401 = "moliyaviy parol noto'g'ri", asosiy
  /// sessiya emas) — bu holatda ekranning o'zi 401'ni alohida ushlaydi.
  Future<dynamic> post(String yol, {Object? tana, String? tokenOverride, bool sessiyaTekshiruvi = true}) async {
    final javob = await http.post(
      _uri(yol),
      headers: _sarlavhalar(tokenOverride),
      body: tana == null ? null : jsonEncode(tana),
    );
    return _javobniQayta(javob, sessiyaTekshiruvi: sessiyaTekshiruvi);
  }

  /// Multipart (fayl) yuklash — masalan offline navbatdan kelgan kip suratini
  /// `POST /kiplar/{id}/surat` ga biriktirish uchun.
  Future<dynamic> postFile(
    String yol, {
    required String maydon,
    required Uint8List baytlar,
    required String faylNomi,
    String? tokenOverride,
  }) async {
    final amaldagiToken = tokenOverride ?? token;
    final sorov = http.MultipartRequest('POST', _uri(yol))
      ..files.add(http.MultipartFile.fromBytes(maydon, baytlar, filename: faylNomi))
      ..headers.addAll({
        if (amaldagiToken != null) 'Authorization': 'Bearer $amaldagiToken',
      });
    final javob = await http.Response.fromStream(await sorov.send());
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
