import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/api/api_exception.dart';
import 'package:kip_tarozi/services/offline_kip_navbati.dart';

/// `POST /kiplar/sinxron` -> "saqlandi", `POST /kiplar/{id}/surat` -> qayd qiladi.
/// `oldindan` — birinchi so'rovdan OLDIN (sinxron davomida yangi kip saqlash).
/// `xatoBerishSorovRaqami` — berilgan bo'lsa, shu tartib raqamli `post()`
/// chaqiruvida (1-dan boshlab) tarmoq xatosi otiladi (bo'lak-xato simulyatsiyasi).
class _SoxtaApi extends ApiClient {
  int postChaqirildi = 0;
  final List<int> bolakHajmlari = []; // har `post()` chaqiruvidagi elementlar soni
  final List<String> suratYuklashlar = [];
  Uint8List? oxirgiSuratBaytlari;
  Future<void> Function()? oldindan;
  bool suratXato = false;
  bool suratTarmoqXato = false;
  int? xatoBerishSorovRaqami;
  Set<String> serverQatiyRadEtadi = const {}; // shu mijoz_id'lar "xato" holat bilan qaytadi

  @override
  Future<dynamic> post(String yol, {Object? tana, String? tokenOverride}) async {
    if (postChaqirildi == 0 && oldindan != null) await oldindan!();
    postChaqirildi++;
    if (xatoBerishSorovRaqami != null && postChaqirildi == xatoBerishSorovRaqami) {
      throw const SocketException('tarmoq yo\'q (bo\'lak sinovi)');
    }
    final list = tana as List;
    bolakHajmlari.add(list.length);
    return list.map((e) {
      final mijozId = (e as Map)['mijoz_id'];
      if (serverQatiyRadEtadi.contains(mijozId)) {
        return {'mijoz_id': mijozId, 'holat': 'xato', 'xabar': 'Partiya topilmadi'};
      }
      return {'mijoz_id': mijozId, 'holat': 'saqlandi', 'kip_id': 1000 + postChaqirildi};
    }).toList();
  }

  @override
  Future<dynamic> postFile(String yol, {required String maydon, required Uint8List baytlar, required String faylNomi, String? tokenOverride}) async {
    if (suratTarmoqXato) throw const SocketException('tarmoq yo\'q');
    if (suratXato) throw ApiException(413, 'juda katta');
    suratYuklashlar.add(yol);
    oxirgiSuratBaytlari = baytlar;
    return {'id': 1, 'surat_yoli': 'http://x/media/y.jpg'};
  }
}

Map<String, dynamic> _tana(String mijozId, {double ogirlik = 100.0}) => {
      'mijoz_id': mijozId,
      'partiya_id': 1,
      'ogirlik': ogirlik,
      'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
      'majburiy': false,
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('boshida navbat bo\'sh', () async {
    expect(await OfflineKipNavbati.uzunlik(), 0);
    expect(await OfflineKipNavbati.royxat(), isEmpty);
  });

  test('qoshish -> navbatda saqlanadi (tana + token + suratYoli)', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('a-1'), token: 'tok-1', suratYoli: r'C:\x\a-1.jpg');
    await OfflineKipNavbati.qoshish(tana: _tana('a-2'), token: 'tok-1');

    final royxat = await OfflineKipNavbati.royxat();
    expect(royxat.length, 2);
    expect((royxat.first['tana'] as Map)['mijoz_id'], 'a-1');
    expect(royxat.first['suratYoli'], r'C:\x\a-1.jpg');
    expect(royxat[1].containsKey('suratYoli'), isFalse);
  });

  test('bir xil mijoz_id ikki marta qo\'shilmaydi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('dup', ogirlik: 10), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('dup', ogirlik: 999), token: 't');
    expect(await OfflineKipNavbati.uzunlik(), 1);
  });

  test('sinxronla: suratsiz kiplarni yuboradi va o\'chiradi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('s-1'), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('s-2'), token: 't');

    final natija = await OfflineKipNavbati.sinxronla(_SoxtaApi());

    expect(natija.yuborilgan, 2);
    expect(await OfflineKipNavbati.uzunlik(), 0);
  });

  test('sinxron DAVOMIDA qo\'shilgan yozuv yo\'qolmaydi (race)', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('race-1'), token: 't');
    final api = _SoxtaApi()..oldindan = () => OfflineKipNavbati.qoshish(tana: _tana('race-2'), token: 't');

    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 1);
    final qolgan = await OfflineKipNavbati.royxat();
    expect(qolgan.length, 1);
    expect((qolgan.single['tana'] as Map)['mijoz_id'], 'race-2');
  });

  test('surat bilan: kip + surat yuboriladi, lokal fayl o\'chiriladi', () async {
    final dir = await Directory.systemTemp.createTemp('offkip');
    final fayl = File('${dir.path}/foto.jpg')..writeAsBytesSync([1, 2, 3, 4, 5]);
    await OfflineKipNavbati.qoshish(tana: _tana('p-1'), token: 't', suratYoli: fayl.path);

    final api = _SoxtaApi();
    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 1);
    expect(natija.songgiKipId, 1001);
    expect(api.suratYuklashlar, ['/kiplar/1001/surat']);
    expect(api.oxirgiSuratBaytlari, [1, 2, 3, 4, 5]);
    expect(await OfflineKipNavbati.uzunlik(), 0);
    expect(fayl.existsSync(), isFalse); // yuklanganidan keyin o'chirilgan
    dir.deleteSync(recursive: true);
  });

  test('surat yuklashda TARMOQ xatosi: kip saqlangan, surat keyingi tsiklda qayta', () async {
    final dir = await Directory.systemTemp.createTemp('offkip');
    final fayl = File('${dir.path}/foto.jpg')..writeAsBytesSync([9, 9, 9]);
    await OfflineKipNavbati.qoshish(tana: _tana('q-1'), token: 't', suratYoli: fayl.path);

    // 1-tsikl: kip ketadi, surat tarmoq xatosi
    final natija1 = await OfflineKipNavbati.sinxronla(_SoxtaApi()..suratTarmoqXato = true);
    expect(natija1.yuborilgan, 1); // kip saqlandi
    final oraliq = await OfflineKipNavbati.royxat();
    expect(oraliq.length, 1);
    expect(oraliq.single['kipId'], 1001); // kip_id yozildi
    expect(fayl.existsSync(), isTrue); // surat hali saqlanib turibdi

    // 2-tsikl: kip qayta yuborilmaydi (kipId bor), faqat surat
    final api2 = _SoxtaApi();
    final natija2 = await OfflineKipNavbati.sinxronla(api2);
    expect(natija2.yuborilgan, 0); // yangi kip yo'q
    expect(api2.postChaqirildi, 0); // /kiplar/sinxron CHAQIRILMADI
    expect(api2.suratYuklashlar, ['/kiplar/1001/surat']);
    expect(await OfflineKipNavbati.uzunlik(), 0);
    expect(fayl.existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  test('surat serverdan RAD etilsa: kip saqlangan, yozuv o\'chiriladi', () async {
    final dir = await Directory.systemTemp.createTemp('offkip');
    final fayl = File('${dir.path}/foto.jpg')..writeAsBytesSync([7]);
    await OfflineKipNavbati.qoshish(tana: _tana('r-1'), token: 't', suratYoli: fayl.path);

    final natija = await OfflineKipNavbati.sinxronla(_SoxtaApi()..suratXato = true);

    expect(natija.yuborilgan, 1);
    expect(await OfflineKipNavbati.uzunlik(), 0); // umidini uzdik, yozuv ketdi
    expect(fayl.existsSync(), isFalse);
    dir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------
  // 5-QISM (audit topilmasi): backend QAT'IY rad etgan ("poison") yozuv
  // navbatdan JIMGINA o'chirilmasin — "muammoli" deb belgilanib, operator
  // ekranida ko'rinadigan bo'lishi kerak.
  // ---------------------------------------------------------------------

  test('backend rad etgan ("xato") yozuv o\'chirilmaydi — "muammoli" deb belgilanadi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('yaxshi-1'), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('yomon-1'), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('yaxshi-2'), token: 't');

    final api = _SoxtaApi()..serverQatiyRadEtadi = {'yomon-1'};
    final natija = await OfflineKipNavbati.sinxronla(api);

    // 2 ta muvaffaqiyatli yuborildi; 1 tasi "muammoli" — natija.yuborilgan'ga
    // kirmaydi, lekin xatolar ro'yxatida ko'rinadi.
    expect(natija.yuborilgan, 2);
    expect(natija.xatolar, ['Partiya topilmadi']);

    // Navbat UMUMAN bo'sh emas — muammoli yozuv HALI HAM saqlangan.
    expect(await OfflineKipNavbati.uzunlik(), 1);
    expect(await OfflineKipNavbati.muammoliSoni(), 1);

    final muammoli = await OfflineKipNavbati.muammoliRoyxat();
    expect(muammoli.length, 1);
    expect((muammoli.single['tana'] as Map)['mijoz_id'], 'yomon-1');
    expect(muammoli.single['muammoliXabari'], 'Partiya topilmadi');
  });

  test('muammoli yozuv KEYINGI sinxronlarda qayta yuborilmaydi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('yomon-2'), token: 't');
    await OfflineKipNavbati.sinxronla(_SoxtaApi()..serverQatiyRadEtadi = {'yomon-2'});
    expect(await OfflineKipNavbati.muammoliSoni(), 1);

    // Endi "server tuzaldi" deb faraz qilsak ham (muammoli belgisi olib
    // tashlanmagani uchun) — qayta so'rov YUBORILMASLIGI kerak.
    final api2 = _SoxtaApi();
    final natija2 = await OfflineKipNavbati.sinxronla(api2);
    expect(api2.postChaqirildi, 0, reason: 'muammoli yozuv uchun qayta so\'rov yuborilmasligi kerak');
    expect(natija2.yuborilgan, 0);
    expect(await OfflineKipNavbati.muammoliSoni(), 1); // hali ham saqlanib turibdi
  });

  test('muammoli yozuv boshqa yaxshi yozuvlar bilan aralash bo\'lakda ham to\'g\'ri ishlaydi', () async {
    for (var i = 0; i < 5; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('aralash-$i'), token: 't');
    }
    final api = _SoxtaApi()..serverQatiyRadEtadi = {'aralash-1', 'aralash-3'};
    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 3); // aralash-0,2,4
    expect(await OfflineKipNavbati.muammoliSoni(), 2); // aralash-1,3
    expect(await OfflineKipNavbati.uzunlik(), 2); // faqat muammolilar navbatda qoldi
  });

  // ---------------------------------------------------------------------
  // AUDIT TOPILMASI TUZATISHI: katta (kunlab offline) navbat endi bitta
  // ulkan so'rov o'rniga kichik bo'laklarga bo'lib yuboriladi.
  // ---------------------------------------------------------------------

  test('katta navbat (220 ta) bo\'laklarga bo\'linib yuboriladi', () async {
    for (var i = 0; i < 220; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('katta-$i'), token: 't');
    }
    expect(await OfflineKipNavbati.uzunlik(), 220);

    final api = _SoxtaApi();
    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 220);
    expect(await OfflineKipNavbati.uzunlik(), 0);
    // 220 ta, 50 tadan bo'lak -> 5 ta so'rov (4x50 + 1x20) — BITTA ULKAN
    // so'rov o'rniga.
    expect(api.postChaqirildi, 5);
    expect(api.bolakHajmlari, [50, 50, 50, 50, 20]);
  });

  test('bo\'lak muvaffaqiyatsiz bo\'lsa — OLDINGI bo\'laklar navbatdan allaqachon o\'chirilgan bo\'ladi', () async {
    for (var i = 0; i < 120; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('bolak-$i'), token: 't');
    }

    // 1-bo'lak (50 ta) muvaffaqiyatli, 2-bo'lakda (so'rov #2) tarmoq xatosi.
    final api = _SoxtaApi()..xatoBerishSorovRaqami = 2;
    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 50); // faqat 1-bo'lak muvaffaqiyatli bo'ldi
    expect(api.postChaqirildi, 2); // 3-bo'lakka umuman yetib bormadi
    expect(api.bolakHajmlari, [50]); // faqat 1-bo'lak natija berdi

    final qolgan = await OfflineKipNavbati.royxat();
    expect(qolgan.length, 70); // 120 - 50 (1-bo'lak) = 70 ta navbatda qoldi
    final qolganIdlar = qolgan.map((y) => (y['tana'] as Map)['mijoz_id']).toSet();
    // Birinchi 50 ta ('bolak-0'..'bolak-49') YO'Q, qolgani BOR.
    for (var i = 0; i < 50; i++) {
      expect(qolganIdlar.contains('bolak-$i'), isFalse, reason: 'bolak-$i allaqachon yuborilgan bo\'lishi kerak edi');
    }
    for (var i = 50; i < 120; i++) {
      expect(qolganIdlar.contains('bolak-$i'), isTrue, reason: 'bolak-$i hali navbatda qolishi kerak edi');
    }
  });

  test('bo\'lak muvaffaqiyatsizligidan keyingi tsikl qolganlarni tugatadi', () async {
    for (var i = 0; i < 120; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('davom-$i'), token: 't');
    }

    // 1-tsikl: 2-bo'lakda uziladi.
    await OfflineKipNavbati.sinxronla(_SoxtaApi()..xatoBerishSorovRaqami = 2);
    expect(await OfflineKipNavbati.uzunlik(), 70);

    // 2-tsikl ("internet tiklandi"): qolgan 70 ta (2 bo'lak: 50+20) muvaffaqiyatli.
    final api2 = _SoxtaApi();
    final natija2 = await OfflineKipNavbati.sinxronla(api2);
    expect(natija2.yuborilgan, 70);
    expect(api2.bolakHajmlari, [50, 20]);
    expect(await OfflineKipNavbati.uzunlik(), 0);
  });

  test('ikki xil operator tokeni alohida guruhlanadi va bo\'laklanadi', () async {
    for (var i = 0; i < 60; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('a-$i'), token: 'tok-A');
    }
    for (var i = 0; i < 10; i++) {
      await OfflineKipNavbati.qoshish(tana: _tana('b-$i'), token: 'tok-B');
    }

    final api = _SoxtaApi();
    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 70);
    // tok-A: 60 ta -> 2 bo'lak (50+10); tok-B: 10 ta -> 1 bo'lak. Jami 3 so'rov.
    expect(api.postChaqirildi, 3);
    expect(api.bolakHajmlari, unorderedEquals([50, 10, 10]));
    expect(await OfflineKipNavbati.uzunlik(), 0);
  });
}
