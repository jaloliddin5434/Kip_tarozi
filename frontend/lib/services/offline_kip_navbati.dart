import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'offline_surat.dart';

/// Internet/server uzilganda operator "Saqlash" bosgan kiplar shu navbatga
/// (SharedPreferences'da JSON ro'yxat) yoziladi va aloqa tiklangach yuboriladi.
///
/// Har yozuv IKKI bosqichda sinxronlanadi:
///  1. Kip ma'lumoti — `POST /kiplar/sinxron` (mijoz_id dedup). Muvaffaqiyatda
///     yozuvga `kipId` yoziladi.
///  2. (agar offline paytda LAN kamerasidan surat olingan bo'lsa) surat —
///     `POST /kiplar/{kipId}/surat` (multipart). Muvaffaqiyatda lokal fayl
///     o'chiriladi.
/// Kip HECH QACHON yo'qolmaydi; surat esa "best-effort" (yuklab bo'lmasa
/// kip suratsiz qoladi).
///
/// Yangi og'ir paket (sqflite/hive) QO'SHILMADI: navbat kichik, shared_preferences
/// yetarli. Surat baytlari SharedPreferences'ga EMAS, alohida lokal faylga
/// yoziladi (JSON shishib ketmasin).
class OfflineKipNavbati {
  static const _kalit = 'offline_kip_navbati_v1';

  /// Navbatga yozish/o'chirishni KETMA-KET bajarish uchun oddiy mutex.
  static Future<void> _kilit = Future<void>.value();

  static Future<T> _qulflab<T>(Future<T> Function() ish) {
    final oldingi = _kilit;
    final tugadi = Completer<void>();
    _kilit = tugadi.future;
    return oldingi.then((_) => ish()).whenComplete(tugadi.complete);
  }

  /// Har biri: `{tana, token, suratYoli?, kipId?, qoshilgan}`.
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

  static String? _mid(Map<String, dynamic> y) => (y['tana'] as Map?)?['mijoz_id'] as String?;

  /// Yozuvni navbatga qo'shadi. Bir xil `mijoz_id` ikki marta qo'shilmaydi.
  /// [suratYoli] — offline olingan surat lokal fayl yo'li (ixtiyoriy).
  static Future<void> qoshish({
    required Map<String, dynamic> tana,
    required String token,
    String? suratYoli,
  }) {
    return _qulflab(() async {
      final yozuvlar = await royxat();
      if (yozuvlar.any((y) => _mid(y) == tana['mijoz_id'])) return;
      yozuvlar.add({
        'tana': tana,
        'token': token,
        'suratYoli': ?suratYoli,
        'qoshilgan': DateTime.now().toIso8601String(),
      });
      await _yoz(yozuvlar);
    });
  }

  /// Navbatni sinxronlaydi. `yuborilgan` — shu tsiklda backend'ga YANGI
  /// yozilgan kip soni (surat holatidan qat'i nazar). `songgiKipId` — shu
  /// tsiklda to'liq tugagan (kip+surat) oxirgi kip id'si (operator ekranidagi
  /// "so'nggi kip surati" panelini yangilash uchun).
  ///
  /// Tarmoq so'rovlari QULFLANMAGAN holda (operator "Saqlash"i bloklanmasin);
  /// faqat navbatni yangilash qulf ostida.
  static Future<({int yuborilgan, List<String> xatolar, int? songgiKipId})> sinxronla(ApiClient api) async {
    final yozuvlar = await royxat();
    if (yozuvlar.isEmpty) return (yuborilgan: 0, xatolar: const <String>[], songgiKipId: null);

    var yuborilgan = 0;
    int? songgiKipId;
    final xatolar = <String>[];
    final ochiriladigan = <String>{}; // to'liq tugagan mijoz_id'lar
    final kipIdlar = <String, int>{}; // kip saqlandi, surat hali kutilmoqda

    for (final yozuv in yozuvlar) {
      final tana = Map<String, dynamic>.from(yozuv['tana'] as Map);
      final mijozId = tana['mijoz_id'] as String;
      final token = yozuv['token'] as String?;
      final suratYoli = yozuv['suratYoli'] as String?;
      var kipId = yozuv['kipId'] as int?;

      // --- 1-bosqich: kip ---
      if (kipId == null) {
        try {
          final javob = await api
              .post('/kiplar/sinxron', tana: [tana], tokenOverride: token)
              .timeout(const Duration(seconds: 10));
          final natija = (javob as List).first as Map<String, dynamic>;
          final holat = natija['holat'];
          if (holat == 'saqlandi' || holat == 'allaqachon_mavjud') {
            kipId = natija['kip_id'] as int?;
            if (kipId != null) kipIdlar[mijozId] = kipId;
            if (holat == 'saqlandi') yuborilgan++;
          } else {
            xatolar.add((natija['xabar'] as String?) ?? 'nomaʼlum xato');
            ochiriladigan.add(mijozId);
            continue;
          }
        } catch (_) {
          break; // tarmoq/server — keyingi tsiklda qayta
        }
      }

      if (kipId == null) break; // saqlandi, lekin kip_id kelmadi — keyingi tsiklda

      // --- 2-bosqich: surat (agar bor bo'lsa) ---
      if (suratYoli == null) {
        songgiKipId = kipId;
        ochiriladigan.add(mijozId);
        continue;
      }
      final baytlar = await suratniOqi(suratYoli);
      if (baytlar == null || baytlar.isEmpty) {
        songgiKipId = kipId; // fayl yo'q (web/o'chirilgan) — kip saqlangan, tugadi
        ochiriladigan.add(mijozId);
        continue;
      }
      try {
        await api
            .postFile('/kiplar/$kipId/surat',
                maydon: 'surat', baytlar: baytlar, faylNomi: '$mijozId.jpg', tokenOverride: token)
            .timeout(const Duration(seconds: 20));
        await suratniOchir(suratYoli);
        songgiKipId = kipId;
        ochiriladigan.add(mijozId);
      } on ApiException {
        await suratniOchir(suratYoli); // server rad etdi — surat umidini uzamiz
        songgiKipId = kipId;
        ochiriladigan.add(mijozId);
      } catch (_) {
        break; // tarmoq — kip saqlangan (kipId yoziladi), surat keyingi tsiklda
      }
    }

    if (ochiriladigan.isNotEmpty || kipIdlar.isNotEmpty) {
      await _qulflab(() async {
        final hozirgi = await royxat();
        final yangi = <Map<String, dynamic>>[];
        for (final y in hozirgi) {
          final mid = _mid(y);
          if (mid != null && ochiriladigan.contains(mid)) continue;
          if (mid != null && kipIdlar.containsKey(mid) && y['kipId'] == null) {
            y['kipId'] = kipIdlar[mid];
          }
          yangi.add(y);
        }
        await _yoz(yangi);
      });
    }

    return (yuborilgan: yuborilgan, xatolar: xatolar, songgiKipId: songgiKipId);
  }
}
