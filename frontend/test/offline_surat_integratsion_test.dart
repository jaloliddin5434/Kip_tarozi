// MANUAL integratsion test — HAQIQIY backend + Stansiya Agent + IP kamera kerak.
// CI'da ishlamaydi. Ishlab chiqarish (Windows desktop) kod yo'lini to'liq
// sinaydi: agentdan surat -> lokal fayl (offline_surat_boshqa) -> ikki bosqichli
// sinxron -> backend'da Oy/Kun/Smena/Mahsulot papkasiga yozilishi.
//
// Ishga tushirish:
//   1. backend:  uvicorn app.main:app --port 8099
//   2. agent:    uvicorn app.services.rs232.station_agent:app --port 8100
//      (backend/.env'da KAMERA_IP/LOGIN/PAROL to'ldirilgan, kamera LANda)
//   3. seed:     operator_a / OperA_2026x mavjud, "tola" mahsuloti, ochiq partiya
//   4. flutter test test/offline_surat_integratsion_test.dart \
//        --dart-define=BE=http://127.0.0.1:8099/api/v1 \
//        --dart-define=AGENT=http://127.0.0.1:8100/kamera/surat \
//        --dart-define=PARTIYA_ID=25

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/services/kamera_agent.dart';
import 'package:kip_tarozi/services/offline_kip_navbati.dart';
import 'package:kip_tarozi/services/offline_surat.dart';

const _be = String.fromEnvironment('BE', defaultValue: 'http://127.0.0.1:8099/api/v1');
const _agent = String.fromEnvironment('AGENT', defaultValue: 'http://127.0.0.1:8100/kamera/surat');
const _partiyaId = int.fromEnvironment('PARTIYA_ID', defaultValue: 25);

void main() {
  test('offline surat: agent -> lokal fayl -> sinxron -> backend papkasi', () async {
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = null;

    final api = ApiClient()..token = null;
    ApiClient.bazaUrl = _be;
    final login = await api.post('/auth/login', tana: {'login': 'operator_a', 'parol': 'OperA_2026x'});
    api.token = login['access_token'] as String;

    // 1) agentdan real surat
    final baytlar = await agentdanSurat(_agent);
    expect(baytlar, isNotNull, reason: 'Agent /kamera/surat JPEG qaytarishi kerak');
    expect(baytlar!.length, greaterThan(1000));

    // 2) lokal faylga (offline_surat_boshqa — Windows/desktop)
    final mijozId = 'itest-${DateTime.now().millisecondsSinceEpoch}';
    final yol = await suratniSaqla(baytlar, mijozId);
    expect(yol, isNotNull);
    expect(File(yol!).existsSync(), isTrue);

    // 3) navbatga qo'yish
    await OfflineKipNavbati.qoshish(
      tana: {
        'mijoz_id': mijozId,
        'partiya_id': _partiyaId,
        'ogirlik': 123.4,
        'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
        'majburiy': true,
      },
      token: api.token!,
      suratYoli: yol,
    );

    // 4) sinxron — kip + surat
    final natija = await OfflineKipNavbati.sinxronla(api);
    expect(natija.yuborilgan, 1);
    expect(natija.songgiKipId, isNotNull);
    expect(await OfflineKipNavbati.uzunlik(), 0, reason: 'navbat tozalanishi kerak');
    expect(File(yol).existsSync(), isFalse, reason: 'lokal surat yuklangach o\'chiriladi');

    // 5) backend'da surat mavjud, papka tuzilmasiga mos
    final kip = await api.get('/kiplar/${natija.songgiKipId}');
    final suratUrl = kip['surat_yoli'] as String?;
    expect(suratUrl, isNotNull);
    expect(suratUrl, contains('/media/'));
    expect(RegExp(r'/\d{4}-\d{2}/\d{4}-\d{2}-\d{2}/Smena_[A-D]/').hasMatch(suratUrl!), isTrue,
        reason: 'Oy/Kun/Smena papka tuzilmasi: $suratUrl');
  });
}
