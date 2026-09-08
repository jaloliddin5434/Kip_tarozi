import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/services/offline_kip_navbati.dart';

/// Har chaqiruvda "saqlandi" qaytaradi. `oldindan` — birinchi so'rovdan OLDIN
/// bajariladi (sinxron davomida operator yangi kip saqlagani simulyatsiyasi).
class _SoxtaApi extends ApiClient {
  int chaqirildi = 0;
  Future<void> Function()? oldindan;

  @override
  Future<dynamic> post(String yol, {Object? tana, String? tokenOverride}) async {
    if (chaqirildi == 0 && oldindan != null) await oldindan!();
    chaqirildi++;
    final list = tana as List;
    return list.map((e) => {'mijoz_id': (e as Map)['mijoz_id'], 'holat': 'saqlandi', 'kip_id': chaqirildi}).toList();
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

  test('qoshish -> navbatda saqlanadi (tana + token)', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('a-1'), token: 'tok-1');
    await OfflineKipNavbati.qoshish(tana: _tana('a-2'), token: 'tok-1');

    expect(await OfflineKipNavbati.uzunlik(), 2);
    final royxat = await OfflineKipNavbati.royxat();
    expect((royxat.first['tana'] as Map)['mijoz_id'], 'a-1');
    expect(royxat.first['token'], 'tok-1');
    expect(royxat.first['qoshilgan'], isNotNull);
  });

  test('bir xil mijoz_id ikki marta qo\'shilmaydi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('dup', ogirlik: 10), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('dup', ogirlik: 999), token: 't');

    expect(await OfflineKipNavbati.uzunlik(), 1);
    expect(((await OfflineKipNavbati.royxat()).single['tana'] as Map)['ogirlik'], 10);
  });

  test('navbat SharedPreferences orqali qayta o\'qilganda saqlanib qoladi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('persist'), token: 't');
    // yangi "sessiya" — mock qiymatlar saqlanib turadi, faqat instance yangi
    expect(await OfflineKipNavbati.uzunlik(), 1);
  });

  test('sinxronla muvaffaqiyatli yozuvlarni o\'chiradi', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('s-1'), token: 't');
    await OfflineKipNavbati.qoshish(tana: _tana('s-2'), token: 't');

    final natija = await OfflineKipNavbati.sinxronla(_SoxtaApi());

    expect(natija.yuborilgan, 2);
    expect(natija.xatolar, isEmpty);
    expect(await OfflineKipNavbati.uzunlik(), 0);
  });

  test('sinxron DAVOMIDA qo\'shilgan yozuv yo\'qolmaydi (race)', () async {
    await OfflineKipNavbati.qoshish(tana: _tana('race-1'), token: 't');

    final api = _SoxtaApi()
      ..oldindan = () => OfflineKipNavbati.qoshish(tana: _tana('race-2'), token: 't');

    final natija = await OfflineKipNavbati.sinxronla(api);

    expect(natija.yuborilgan, 1); // faqat race-1 yuborildi
    final qolgan = await OfflineKipNavbati.royxat();
    expect(qolgan.length, 1);
    expect((qolgan.single['tana'] as Map)['mijoz_id'], 'race-2'); // race-2 saqlanib qoldi
  });
}
