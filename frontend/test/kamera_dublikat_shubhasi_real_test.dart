// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — qarang:
// operator_oqimi_test.dart izohi (bir xil naqsh). AUDIT TUZATISHI: kamera
// ishlamay qolganda (POST /kiplar -> 202) dublikat-og'irlik ogohlantirishi
// ENDI admin panelida ("Tasdiqlash tarixi" — "Kamera tasdiqlari" bilan "Kip
// to'g'irlash so'rovlari"ni birlashtirgan ekran) ko'rinishini REAL backend +
// REAL admin ekrani orqali tasdiqlaydi — aynan avvalgi audit stsenariysini
// (bitta partiyaga 2 soniya farq bilan bir xil og'irlik, kamera o'chirilgan)
// qayta takrorlab. Merged ro'yxatda boshqa turdagi (kip-to'g'irlash)
// qatorlar ham bo'lishi mumkinligi uchun barcha tekshiruvlar aynan shu
// partiya raqami ko'rinadigan qatorlar bilan CHEGARALANGAN.
//
// Ishga tushirish:
//   1. Ajratilgan test bazasida migratsiya bajarilgan, admin
//      (login "audit_admin"/AuditAdmin123!) va operator_a
//      (login "operator_a"/smenaA123) mavjud bo'lsin. KAMERA_IP
//      unreachable (masalan 10.255.255.1) bo'lsin.
//   2. uvicorn app.main:app --port 8010 shu bazaga ulangan holda ishlasin.
//   3. flutter test test/kamera_dublikat_shubhasi_real_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _uuid = Uuid();

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _adminLogin = String.fromEnvironment('ADMIN_LOGIN', defaultValue: 'audit_admin');
const _adminParoli = String.fromEnvironment('ADMIN_PAROLI', defaultValue: 'AuditAdmin123!');
const _operatorLogin = String.fromEnvironment('OPERATOR_LOGIN', defaultValue: 'operator_a');
const _operatorParoli = String.fromEnvironment('OPERATOR_PAROLI', defaultValue: 'smenaA123');

Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

/// Avvalgi audit stsenariysini AYNAN takrorlaydi: operator_a real login
/// qilib, bitta partiyaga (yangi, tasodifiy raqam) 2 soniya farq bilan
/// ikkita bir xil (77.0 kg) so'rov yuboradi — kamera unreachable bo'lgani
/// uchun ikkalasi ham 202 (kamera_tasdiq_kutilmoqda) qaytaradi.
Future<int> _ikkitaYaqinSorovYaratish() async {
  final loginJavobi = await http.post(
    Uri.parse('$_backendUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': _operatorLogin, 'parol': _operatorParoli}),
  );
  final opToken = (jsonDecode(loginJavobi.body) as Map)['access_token'] as String;

  final partiyaRaqami = 900000 + DateTime.now().millisecondsSinceEpoch % 90000;
  final partiyaJavobi = await http.post(
    Uri.parse('$_backendUrl/partiyalar'),
    headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'mahsulot_kodi': 'tola', 'partiya_raqami': partiyaRaqami}),
  );
  final partiyaId = (jsonDecode(partiyaJavobi.body) as Map)['id'];

  Future<void> kipYubor(String mijozId) async {
    final javob = await http.post(
      Uri.parse('$_backendUrl/kiplar'),
      headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'mijoz_id': mijozId,
        'partiya_id': partiyaId,
        'ogirlik': 77.0,
        'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
        'majburiy': false,
      }),
    );
    // ignore: avoid_print
    print('DEBUG POST /kiplar -> ${javob.statusCode}: ${javob.body}');
  }

  // mijoz_id backendda VARCHAR(36) — haqiqiy operator ilovasi kabi UUID
  // ishlatamiz (uzun tavsifiy satr emas).
  await kipYubor(_uuid.v4());
  await Future.delayed(const Duration(seconds: 2));
  await kipYubor(_uuid.v4());

  return partiyaRaqami;
}

void main() {
  testWidgets(
    'REAL: Admin panelida "Tasdiqlash tarixi" ro\'yxatida dublikat-shubhasi ogohlantirishi (sariq belgi) ko\'rinadi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        ApiClient.bazaUrl = _backendUrl;

        // --- Avvalgi audit stsenariysini AYNAN takrorlaymiz ---
        final partiyaRaqami = await _ikkitaYaqinSorovYaratish();
        // ignore: avoid_print
        print('REAL SINOV: partiya #$partiyaRaqami ga 2s farq bilan ikkita 77.0kg so\'rov yuborildi.');

        await tester.pumpWidget(const KipTaroziApp());
        await _kut(tester, marta: 3);

        // --- Admin sifatida REAL login ---
        await tester.tap(find.text('Admin'));
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, _adminLogin);
        await tester.pump();
        await tester.enterText(find.byType(TextField).at(1), _adminParoli);
        await tester.pump();
        await tester.tap(find.text('Kirish'));
        await _kut(tester, marta: 6);

        // --- "Tasdiqlash tarixi" (birlashtirilgan) bo'limiga o'tamiz ---
        await tester.tap(find.text('Tasdiqlash tarixi').first);
        await _kut(tester, marta: 10);

        if (find.textContaining('#$partiyaRaqami').evaluate().isEmpty) {
          final matnlar = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList();
          // ignore: avoid_print
          print('DEBUG joriy matnlar: $matnlar');
        }

        // Kutilayotgan (yangi yaratilgan) ikkita qatorni topamiz.
        final buPartiyaMatni = find.textContaining('#$partiyaRaqami');
        expect(
          buPartiyaMatni,
          findsNWidgets(2),
          reason: 'Ikkala yaqinda yaratilgan so\'rov ham ro\'yxatda ko\'rinishi kerak',
        );

        // Merged ro'yxatda boshqa turdagi (kip-to'g'irlash) qatorlar ham
        // bo'lishi mumkin — qolgan tekshiruvlarni aynan shu ikkita qator
        // (partiya raqami orqali topilgan DataRow'lar) bilan chegaralaymiz.
        final buPartiyaQatorlari = find.ancestor(of: buPartiyaMatni, matching: find.byType(DataRow));
        expect(buPartiyaQatorlari, findsNWidgets(2));

        // --- ASOSIY TASDIQ: ikkala qatorda ham sariq ogohlantirish belgisi ---
        final ogohlantirishBelgisi = find.descendant(
          of: buPartiyaQatorlari,
          matching: find.byIcon(Icons.warning_amber_rounded),
        );
        expect(
          ogohlantirishBelgisi,
          findsNWidgets(2),
          reason: 'REAL: har ikkala yaqin (2s, bir xil og\'irlik) so\'rov uchun ham sariq dublikat-shubhasi belgisi ko\'rinishi kerak',
        );

        // Admin BARIBIR tasdiqlashi mumkinligini ham tasdiqlaymiz (avtomatik
        // bloklanmagan — faqat ko'rinadigan ogohlantirish).
        final tasdiqlashTugmalari = find.descendant(of: buPartiyaQatorlari, matching: find.text('Tasdiqlash'));
        expect(tasdiqlashTugmalari, findsNWidgets(2));
      });
    },
  );
}
