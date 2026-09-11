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

  /// AUDIT TOPILMASI (tuzatilmoqda, Stansiya Agent — sinxron.py bilan bir
  /// xil naqsh): kip ma'lumotlari (`/kiplar/sinxron`) endi BIR-BIR emas,
  /// shu miqdordan BO'LAKLARGA bo'lib yuboriladi — kunlar offline turgandan
  /// keyin navbatda yuzlab yozuv to'plansa, bittalab yuborish juda ko'p
  /// (sekin) alohida tarmoq so'rovi talab qilardi. Bitta so'rovda bir nechta
  /// yozuv yuborish (backend allaqachon ro'yxat qabul qiladi) sinxronni
  /// sezilarli tezlashtiradi, ayni paytda bo'lak hajmi kichik saqlanib
  /// (so'rov hech qachon vaqt tugashiga yetib bormasin uchun) xavfsiz
  /// qoladi. Har bo'lak yuborilgach DARHOL navbatdan o'chiriladi — keyingi
  /// bo'lak muvaffaqiyatsiz bo'lsa ham oldingilar yo'qolmaydi.
  static const int _bolakHajmi = 50;
  static const Duration _bolakTaymeri = Duration(seconds: 60);

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

  /// 5-QISM (audit topilmasi): backend qat'iy rad etgan ("poison", masalan
  /// "Partiya topilmadi") yozuvlar SONI — bular navbatdan JIMGINA
  /// o'chirilmaydi (avvalgidek), balki shu yerda "muammoli" deb qolib,
  /// operator ekranida ko'rinadigan ogohlantirish banneri uchun ishlatiladi.
  static Future<int> muammoliSoni() async => (await royxat()).where((y) => y['muammoli'] == true).length;

  /// Muammoli (dead-letter) yozuvlarning to'liq ro'yxati — kerak bo'lsa
  /// tafsilot ko'rsatish uchun.
  static Future<List<Map<String, dynamic>>> muammoliRoyxat() async =>
      (await royxat()).where((y) => y['muammoli'] == true).toList();

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

  /// Navbatdagi `ochiriladigan` (to'liq tugagan) mijoz_id'larni olib
  /// tashlaydi va `kipIdlar`ni yozadi — HAR BO'LAK/YOZUVDAN KEYIN alohida
  /// chaqiriladi (bitta katta yakuniy commit emas), shunda navbat har doim
  /// "shu paytgacha haqiqatan bajarilgan ish"ni aks ettiradi — sinxronlash
  /// o'rtada uzilib qolsa (masalan ilova yopilsa) ham allaqachon
  /// muvaffaqiyatli bo'lgan qism yo'qolmaydi.
  static Future<void> _navbatgaQollash({
    required Set<String> ochiriladigan,
    required Map<String, int> kipIdlar,
    Map<String, String> muammoli = const {},
  }) {
    if (ochiriladigan.isEmpty && kipIdlar.isEmpty && muammoli.isEmpty) return Future.value();
    return _qulflab(() async {
      final hozirgi = await royxat();
      final yangi = <Map<String, dynamic>>[];
      for (final y in hozirgi) {
        final mid = _mid(y);
        if (mid != null && ochiriladigan.contains(mid)) continue;
        if (mid != null && kipIdlar.containsKey(mid) && y['kipId'] == null) {
          y['kipId'] = kipIdlar[mid];
        }
        // 5-QISM: backend qat'iy rad etgan yozuv navbatdan O'CHIRILMAYDI —
        // "muammoli" deb belgilanadi (ma'lumot saqlanadi, operator ekranida
        // ogohlantirish sifatida ko'rinadi), faqat KEYINGI sinxronlarda
        // qayta yuborilmasligi uchun bekor qilingan kabi filtrlanadi.
        if (mid != null && muammoli.containsKey(mid)) {
          y['muammoli'] = true;
          y['muammoliXabari'] = muammoli[mid];
        }
        yangi.add(y);
      }
      await _yoz(yangi);
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
    var yuborilgan = 0;
    int? songgiKipId;
    final xatolar = <String>[];

    // =========================================================
    // 1-BOSQICH — kip ma'lumotlari, TOKEN bo'yicha guruhlab, har guruhni
    // BO'LAKLARGA (_bolakHajmi) bo'lib, bitta so'rovda bir nechta yozuv.
    // =========================================================
    final kutilayotgan = (await royxat()).where((y) => y['kipId'] == null && y['muammoli'] != true).toList();
    final tokenBoyicha = <String?, List<Map<String, dynamic>>>{};
    for (final y in kutilayotgan) {
      tokenBoyicha.putIfAbsent(y['token'] as String?, () => []).add(y);
    }

    var toxtatildi = false;
    for (final guruh in tokenBoyicha.entries) {
      if (toxtatildi) break;
      final token = guruh.key;
      final elementlar = guruh.value;

      for (var i = 0; i < elementlar.length; i += _bolakHajmi) {
        final bolak = elementlar.skip(i).take(_bolakHajmi).toList();
        final tanalar = bolak.map((y) => Map<String, dynamic>.from(y['tana'] as Map)).toList();

        List<dynamic> natijalar;
        try {
          final javob = await api.post('/kiplar/sinxron', tana: tanalar, tokenOverride: token).timeout(_bolakTaymeri);
          natijalar = javob as List;
        } catch (_) {
          // Tarmoq/server xatosi — shu bo'lak (va navbatdagi bo'lak/guruhlar)
          // KEYINGI TSIKLGA qoladi; bu bo'lakdan OLDINGI bo'laklar allaqachon
          // pastda alohida-alohida navbatdan o'chirilgan — yo'qolmagan.
          toxtatildi = true;
          break;
        }

        final kipIdlarBolak = <String, int>{};
        final muammoliBolak = <String, String>{};
        for (final natijaXom in natijalar) {
          final natija = natijaXom as Map<String, dynamic>;
          final mijozId = natija['mijoz_id'] as String;
          final holat = natija['holat'];
          if (holat == 'saqlandi' || holat == 'allaqachon_mavjud') {
            final kipId = natija['kip_id'] as int?;
            if (kipId != null) kipIdlarBolak[mijozId] = kipId;
            if (holat == 'saqlandi') yuborilgan++;
          } else {
            // 5-QISM (audit topilmasi): backend bu yozuvni QAT'IY rad etdi
            // (masalan "Partiya topilmadi") — avval navbatdan JIMGINA
            // o'chirilardi (ma'lumot yo'qolardi). Endi "muammoli" deb
            // belgilanadi — qayta yuborilmaydi, LEKIN yo'qolmaydi, operator
            // ekranida ko'rinadigan ogohlantirish orqali ma'lum bo'ladi.
            final xabar = (natija['xabar'] as String?) ?? 'nomaʼlum xato';
            xatolar.add(xabar);
            muammoliBolak[mijozId] = xabar;
          }
        }

        // Shu BO'LAK darhol navbatdan olib tashlanadi/yangilanadi — keyingi
        // bo'lak muvaffaqiyatsiz bo'lib qolsa ham bu bo'lak yo'qolmaydi.
        await _navbatgaQollash(ochiriladigan: const {}, kipIdlar: kipIdlarBolak, muammoli: muammoliBolak);
      }
    }

    // =========================================================
    // 2-BOSQICH — suratlar. Multipart fayl yuklash bo'lganligi uchun
    // bo'laklarga bo'lib bo'lmaydi (backendda ko'p-fayl endpointi yo'q va
    // bu vazifa doirasida qo'shilmaydi) — bittalab, lekin har biri
    // muvaffaqiyatidan so'ng DARHOL navbatdan o'chiriladi (avvalgidek).
    // 1-bosqichda navbat allaqachon yangilangan — shu YANGI holatni o'qiymiz.
    // =========================================================
    final suratKutilayotgan = (await royxat()).where((y) => y['kipId'] != null && y['suratYoli'] != null).toList();
    for (final yozuv in suratKutilayotgan) {
      final mijozId = _mid(yozuv);
      final kipId = yozuv['kipId'] as int?;
      if (mijozId == null || kipId == null) continue;
      final token = yozuv['token'] as String?;
      final suratYoli = yozuv['suratYoli'] as String;

      final baytlar = await suratniOqi(suratYoli);
      if (baytlar == null || baytlar.isEmpty) {
        songgiKipId = kipId; // fayl yo'q (web/o'chirilgan) — kip saqlangan, tugadi
        await _navbatgaQollash(ochiriladigan: {mijozId}, kipIdlar: const {});
        continue;
      }
      try {
        await api
            .postFile('/kiplar/$kipId/surat',
                maydon: 'surat', baytlar: baytlar, faylNomi: '$mijozId.jpg', tokenOverride: token)
            .timeout(const Duration(seconds: 20));
        await suratniOchir(suratYoli);
        songgiKipId = kipId;
        await _navbatgaQollash(ochiriladigan: {mijozId}, kipIdlar: const {});
      } on ApiException {
        await suratniOchir(suratYoli); // server rad etdi — surat umidini uzamiz
        songgiKipId = kipId;
        await _navbatgaQollash(ochiriladigan: {mijozId}, kipIdlar: const {});
      } catch (_) {
        break; // tarmoq — kip saqlangan (kipId yozilgan), surat keyingi tsiklda
      }
    }

    // Suratsiz, lekin kip_id allaqachon olingan yozuvlar (masalan offline
    // paytda kamera surat bermagan) — navbatda "kipId bor-u, surat yo'q"
    // holida qolib ketmasin, shu yerda ham tugallanadi.
    final suratsizTugagan = (await royxat()).where((y) => y['kipId'] != null && y['suratYoli'] == null).toList();
    if (suratsizTugagan.isNotEmpty) {
      final ochiriladigan = <String>{};
      for (final y in suratsizTugagan) {
        final mid = _mid(y);
        if (mid == null) continue;
        songgiKipId = y['kipId'] as int?;
        ochiriladigan.add(mid);
      }
      await _navbatgaQollash(ochiriladigan: ochiriladigan, kipIdlar: const {});
    }

    return (yuborilgan: yuborilgan, xatolar: xatolar, songgiKipId: songgiKipId);
  }
}
