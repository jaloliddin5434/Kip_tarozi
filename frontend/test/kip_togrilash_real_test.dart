// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — qarang:
// operator_oqimi_test.dart va kamera_dublikat_shubhasi_real_test.dart
// izohlari (bir xil naqsh). AUDIT TUZATISHI (UX birlashtirish): "Kamera
// tasdiqlari" va "Kip to'g'irlash so'rovlari" endi BITTA "Tasdiqlash tarixi"
// ekraniga (`tasdiqlash_tarixi_screen.dart`, GET /tasdiqlash-tarixi) birlashgan
// — bu test REAL backend orqali ro'yxat/tasdiqlash/avto-yangilanish shu
// birlashtirilgan ekranda ham avvalgidek ishlashini tasdiqlaydi. Merged
// ro'yxatda boshqa turdagi (kamera) qatorlar ham bo'lishi mumkinligi uchun
// "Tasdiqlash" tugmasi aynan SHU zayavka qatoridan qidiriladi (global emas).
//
// Ishga tushirish:
//   1. Ajratilgan test bazasida migratsiya bajarilgan, admin
//      (login "audit_admin"/AuditAdmin123!) va operator_a
//      (login "operator_a"/smenaA123) mavjud bo'lsin.
//   2. uvicorn app.main:app --port 8010 shu bazaga ulangan holda ishlasin.
//   3. flutter test test/kip_togrilash_real_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1

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

/// Real operator sifatida: partiya ochib, KAMERASIZ (kamera unreachable —
/// backend 202 qaytaradi) kip saqlaydi, admin sifatida darhol tasdiqlab
/// (haqiqiy kip_id olib), operator nomidan `/kip-togrilash` zayavkasi
/// yuboradi. Zayavka id'ini va sabab matnini qaytaradi.
Future<(int zayavkaId, String sabab, int eskiPartiya, int yangiPartiya)> _realZayavkaYaratish() async {
  Future<String> login(String l, String p) async {
    final j = await http.post(
      Uri.parse('$_backendUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'login': l, 'parol': p}),
    );
    return (jsonDecode(j.body) as Map)['access_token'] as String;
  }

  final opToken = await login(_operatorLogin, _operatorParoli);
  final adminToken = await login(_adminLogin, _adminParoli);

  final eskiPartiyaRaqami = 600000 + DateTime.now().millisecondsSinceEpoch % 90000;
  final eskiPartiyaJavobi = await http.post(
    Uri.parse('$_backendUrl/partiyalar'),
    headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'mahsulot_kodi': 'tola', 'partiya_raqami': eskiPartiyaRaqami}),
  );
  final eskiPartiyaId = (jsonDecode(eskiPartiyaJavobi.body) as Map)['id'];

  final kipJavobi = await http.post(
    Uri.parse('$_backendUrl/kiplar'),
    headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'mijoz_id': _uuid.v4(),
      'partiya_id': eskiPartiyaId,
      'ogirlik': 88.0,
      'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
      'majburiy': false,
    }),
  );
  // Kamera unreachable -> 202 kamera_tasdiq_kutilmoqda; admin darhol tasdiqlaydi.
  final sorovId = (jsonDecode(kipJavobi.body) as Map)['sorov_id'];
  final tasdiqJavobi = await http.post(
    Uri.parse('$_backendUrl/kamera-tasdiq/$sorovId/tasdiqlash'),
    headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
  );
  final kipId = (jsonDecode(tasdiqJavobi.body) as Map)['kip_id'];

  final yangiPartiyaRaqami = 600000 + DateTime.now().millisecondsSinceEpoch % 90000 + 1;
  final yangiPartiyaJavobi = await http.post(
    Uri.parse('$_backendUrl/partiyalar'),
    headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'mahsulot_kodi': 'lint', 'partiya_raqami': yangiPartiyaRaqami}),
  );
  final yangiPartiyaId = (jsonDecode(yangiPartiyaJavobi.body) as Map)['id'];
  // ignore: unused_local_variable
  final _ = yangiPartiyaId;

  // Har testda o'ziga xos matn — oldingi (tugallanmagan) test yozuvlari
  // bilan aralashib ketmasligi uchun partiya raqami qo'shiladi ("#"siz —
  // aks holda `find.textContaining('#...')` partiya izlashda shu matnga
  // ham mos kelib qolardi).
  final sabab = 'Real sinov (partiya kodi $eskiPartiyaRaqami): operator noto\'g\'ri mahsulot tanlagan';
  final zayavkaJavobi = await http.post(
    Uri.parse('$_backendUrl/kip-togrilash'),
    headers: {'Authorization': 'Bearer $opToken', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'kip_id': kipId,
      'yangi_mahsulot_kodi': 'lint',
      'yangi_partiya_raqami': yangiPartiyaRaqami,
      'sabab': sabab,
    }),
  );
  final zayavkaId = (jsonDecode(zayavkaJavobi.body) as Map)['id'] as int;
  return (zayavkaId, sabab, eskiPartiyaRaqami, yangiPartiyaRaqami);
}

void main() {
  testWidgets(
    'REAL: Admin panelida "Kip to\'g\'rilash so\'rovlari" ro\'yxati, ko\'rinishi va tasdiqlash avvalgidek ishlaydi (refaktordan keyin)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        ApiClient.bazaUrl = _backendUrl;

        final (zayavkaId, sabab, eskiPartiya, yangiPartiya) = await _realZayavkaYaratish();
        // ignore: avoid_print
        print('REAL SINOV: zayavka #$zayavkaId yaratildi (eski partiya #$eskiPartiya -> yangi #$yangiPartiya).');

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
        await _kut(tester, marta: 8);

        // --- "Tasdiqlash tarixi" (birlashtirilgan) bo'limiga o'tamiz ---
        await tester.tap(find.text('Tasdiqlash tarixi').first);
        await _kut(tester, marta: 10);

        // Ro'yxatda eski/yangi partiya raqamlari va sabab ko'rinishi kerak
        // (ikkalasi ham BITTA "tavsif" katakchasida — qarang tasdiqlash_tarixi_screen.dart).
        expect(find.textContaining('#$eskiPartiya'), findsOneWidget, reason: 'Eski partiya ro\'yxatda ko\'rinishi kerak');
        expect(find.textContaining('#$yangiPartiya'), findsOneWidget, reason: 'Yangi partiya ro\'yxatda ko\'rinishi kerak');
        expect(find.text(sabab), findsOneWidget, reason: 'Sabab matni to\'liq ko\'rinishi kerak');

        // Merged ro'yxatda boshqa turdagi (kamera) qatorlar ham bo'lishi
        // mumkin — "Tasdiqlash" tugmasini GLOBAL emas, aynan shu zayavka
        // qatori (sabab matni orqali topilgan DataRow) ICHIDAN qidiramiz.
        final buQator = find.ancestor(of: find.text(sabab), matching: find.byType(DataRow));
        expect(buQator, findsOneWidget);
        final tasdiqlashTugmasi = find.descendant(of: buQator, matching: find.text('Tasdiqlash'));
        expect(tasdiqlashTugmasi, findsOneWidget);

        // --- Tasdiqlaymiz --- (jadval keng — gorizontal scroll ichida
        // ko'rinadigan qilib olamiz, aks holda tugma ekran tashqarisida
        // qolib, tap "quruq" ketishi mumkin)
        await tester.ensureVisible(tasdiqlashTugmasi);
        await tester.tap(tasdiqlashTugmasi);
        await _kut(tester, marta: 8);

        // Tasdiqlangach — "Tasdiqlash"/"Rad etish" tugmalari yo'qoladi
        // (default filtr "faqat kutilmoqda" bo'lgani uchun qator umuman
        // ro'yxatdan yo'qoladi — avto-yangilanish + filtr).
        expect(find.textContaining('#$eskiPartiya'), findsNothing, reason: 'Tasdiqlangach "kutilmoqda" filtridan chiqib ketishi kerak');

        // "Kutilmoqda" filtrini o'chirib, hal qilingan holatda ko'ramiz.
        // FilterChip matni "Kutilmoqda..." (ellipsis bilan) — holat-chipdagi
        // xuddi shu matn bilan chalkashmasin uchun aynan FilterChip'ni izlaymiz.
        await tester.tap(find.widgetWithText(FilterChip, 'Kutilmoqda...'));
        await _kut(tester, marta: 5);
        expect(find.textContaining('#$eskiPartiya'), findsOneWidget, reason: 'Filtr o\'chirilgach yana ko\'rinishi kerak');
        expect(find.text('Audit Admin'), findsWidgets, reason: 'Hal qilgan admin ismi ko\'rinishi kerak');
      });
    },
  );
}
