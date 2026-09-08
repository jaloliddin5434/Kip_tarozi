import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/api/api_exception.dart';
import 'package:kip_tarozi/services/offline_kip_navbati.dart';

/// `POST /kiplar/sinxron` -> "saqlandi", `POST /kiplar/{id}/surat` -> qayd qiladi.
/// `oldindan` — birinchi so'rovdan OLDIN (sinxron davomida yangi kip saqlash).
class _SoxtaApi extends ApiClient {
  int postChaqirildi = 0;
  final List<String> suratYuklashlar = [];
  Uint8List? oxirgiSuratBaytlari;
  Future<void> Function()? oldindan;
  bool suratXato = false;
  bool suratTarmoqXato = false;

  @override
  Future<dynamic> post(String yol, {Object? tana, String? tokenOverride}) async {
    if (postChaqirildi == 0 && oldindan != null) await oldindan!();
    postChaqirildi++;
    final list = tana as List;
    return list
        .map((e) => {'mijoz_id': (e as Map)['mijoz_id'], 'holat': 'saqlandi', 'kip_id': 1000 + postChaqirildi})
        .toList();
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
}
