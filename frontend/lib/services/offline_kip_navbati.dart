import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Internet/server uzilganda operator "Saqlash" bosgan kiplar shu navbatga
/// (SharedPreferences'da JSON ro'yxat) yoziladi va aloqa tiklangach
/// `POST /kiplar/sinxron` orqali ketma-ket yuboriladi.
///
/// Yangi og'ir paket (sqflite/hive) QO'SHILMADI: navbat kichik (bir smenada
/// bir necha yozuv), token saqlash uchun allaqachon ishlatilayotgan
/// `shared_preferences` yetarli. Dublikat oldini olish client-generated
/// `mijoz_id` orqali — backend `/kiplar/sinxron` va `/kiplar` ikkalasida ham
/// shu ID bo'yicha tekshiradi.
class OfflineKipNavbati {
  static const _kalit = 'offline_kip_navbati_v1';

  /// Navbatga yozish/o'chirish amallarini KETMA-KET bajarish uchun oddiy
  /// mutex — fon-sinxron va operator "Saqlash" bir vaqtda navbatni
  /// o'zgartirsa, biri ikkinchisining yozuvini bosib ketmasligi uchun.
  static Future<void> _kilit = Future<void>.value();

  static Future<T> _qulflab<T>(Future<T> Function() ish) {
    final oldingi = _kilit;
    final tugadi = Completer<void>();
    _kilit = tugadi.future;
    return oldingi.then((_) => ish()).whenComplete(tugadi.complete);
  }

  /// Kutilayotgan yozuvlar. Har biri: `{tana: {POST /kiplar tanasi},
  /// token: "operator tokeni", qoshilgan: "ISO vaqt"}`.
  static Future<List<Map<String, dynamic>>> royxat() async {
    final prefs = await SharedPreferences.getInstance();
    final xom = prefs.getString(_kalit);
    if (xom == null || xom.isEmpty) return [];
    try {
      return (jsonDecode(xom) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<int> uzunlik() async => (await royxat()).length;

  static Future<void> _yoz(List<Map<String, dynamic>> yozuvlar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kalit, jsonEncode(yozuvlar));
  }

  /// Yozuvni navbatga qo'shadi. Bir xil `mijoz_id` ikki marta qo'shilmaydi.
  static Future<void> qoshish({required Map<String, dynamic> tana, required String token}) {
    return _qulflab(() async {
      final yozuvlar = await royxat();
      final mijozId = tana['mijoz_id'];
      if (yozuvlar.any((y) => (y['tana'] as Map?)?['mijoz_id'] == mijozId)) return;
      yozuvlar.add({
        'tana': tana,
        'token': token,
        'qoshilgan': DateTime.now().toIso8601String(),
      });
      await _yoz(yozuvlar);
    });
  }

  /// Navbatni ketma-ket yuboradi. Har yozuv o'z tokeni bilan, bitta elementli
  /// ro'yxat sifatida `POST /kiplar/sinxron` orqali ketadi:
  ///  - `saqlandi` / `allaqachon_mavjud` -> navbatdan o'chiriladi (muvaffaqiyat)
  ///  - `xato` (masalan partiya yopilgan) -> navbatdan o'chiriladi, [xatolar]ga qo'shiladi
  ///  - tarmoq/server xatosi -> to'xtaydi, qolgan yozuvlar saqlanadi (keyingi tsiklda qayta)
  ///
  /// Tarmoq so'rovlari QULFLANMAGAN holda bajariladi (operator "Saqlash"i
  /// bloklanmasin); faqat navbatdan o'chirish qulf ostida — shu vaqt ichida
  /// qo'shilgan yangi yozuvlar yo'qolmaydi.
  static Future<({int yuborilgan, List<String> xatolar})> sinxronla(ApiClient api) async {
    final yozuvlar = await royxat();
    if (yozuvlar.isEmpty) return (yuborilgan: 0, xatolar: const <String>[]);

    var yuborilgan = 0;
    final xatolar = <String>[];
    final ochiriladigan = <String>{}; // ishlangan (muvaffaqiyat yoki "xato") mijoz_id'lar

    for (final yozuv in yozuvlar) {
      final tana = Map<String, dynamic>.from(yozuv['tana'] as Map);
      final mijozId = tana['mijoz_id'] as String;
      final token = yozuv['token'] as String?;
      try {
        final javob = await api
            .post('/kiplar/sinxron', tana: [tana], tokenOverride: token)
            .timeout(const Duration(seconds: 10));
        final natija = (javob as List).first as Map<String, dynamic>;
        final holat = natija['holat'];
        if (holat == 'saqlandi' || holat == 'allaqachon_mavjud') {
          yuborilgan++;
          ochiriladigan.add(mijozId);
        } else {
          xatolar.add((natija['xabar'] as String?) ?? 'nomaʼlum xato');
          ochiriladigan.add(mijozId);
        }
      } catch (_) {
        // ApiException (401/5xx) yoki tarmoq/timeout — hali yuborilmadi.
        break;
      }
    }

    if (ochiriladigan.isNotEmpty) {
      await _qulflab(() async {
        final hozirgi = await royxat();
        final qolgan = hozirgi
            .where((y) => !ochiriladigan.contains((y['tana'] as Map?)?['mijoz_id']))
            .toList();
        await _yoz(qolgan);
      });
    }

    return (yuborilgan: yuborilgan, xatolar: xatolar);
  }
}
