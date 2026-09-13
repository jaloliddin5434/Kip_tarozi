// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — CI'da emas, faqat
// dev vaqtida qo'lda ishga tushiriladi (qarang: operator_oqimi_test.dart
// izohi — bir xil naqsh). AUDIT TUZATISHI: markazlashgan "401 = avtomatik
// logout" mexanizmini HAQIQIY backend + HAQIQIY admin "tokenlarni bekor
// qilish" endpointi bilan REAL sinaydi (sessiya_tugashi_test.dart soxta
// loopback server bilan xuddi shu narsani tez/deterministik sinaydi).
//
// Ishga tushirish:
//   1. Ajratilgan test bazasida (production EMAS!) migratsiya bajarilgan,
//      admin (login "audit_admin"/AuditAdmin123!) va operator_a
//      (login "operator_a"/smenaA123) foydalanuvchilar mavjud bo'lsin.
//      KAMERA_IP unreachable qiymatga sozlangan bo'lsin (masalan
//      10.255.255.1) — shunda "kamera_tasdiq_kutilmoqda" oqimi xavfsiz
//      (real kameraga tegmasdan) qayta hosil qilinadi.
//   2. uvicorn app.main:app --port 8010 shu (ajratilgan) bazaga ulangan
//      holda ishga tushirilgan bo'lsin.
//   3. flutter test test/sessiya_tugashi_real_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _adminLogin = String.fromEnvironment('ADMIN_LOGIN', defaultValue: 'audit_admin');
const _adminParoli = String.fromEnvironment('ADMIN_PAROLI', defaultValue: 'AuditAdmin123!');
const _operatorParoli = String.fromEnvironment('OPERATOR_PAROLI', defaultValue: 'smenaA123');

Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

/// Admin sifatida REAL login qilib, `operator_a` hisobining BARCHA
/// tokenlarini bekor qiladi — aynan Sozlamalar ekranidagi "Tokenlarni bekor
/// qilish" tugmasi qiladigan HAQIQIY HTTP so'rov (`sozlamalar_screen.dart`).
Future<void> _adminOperatorTokeniniBekorQilsin() async {
  final loginJavobi = await http.post(
    Uri.parse('$_backendUrl/auth/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': _adminLogin, 'parol': _adminParoli}),
  );
  if (loginJavobi.statusCode != 200) {
    throw StateError('Admin login muvaffaqiyatsiz (${loginJavobi.statusCode}): ${loginJavobi.body}');
  }
  final adminToken = (jsonDecode(loginJavobi.body) as Map)['access_token'] as String;

  final menJavobi = await http.get(
    Uri.parse('$_backendUrl/auth/men'),
    headers: {'Authorization': 'Bearer $adminToken'},
  );
  final operatorId = (jsonDecode(menJavobi.body) as Map)['id'];
  // operator_a odatda id=2 (admin=1 dan keyin birinchi seed qilingan) — lekin
  // ANIQ topish uchun to'g'ridan-to'g'ri backenddan so'ramaymiz (bunday
  // endpoint yo'q); shuning uchun operatorId ni environment orqali ham
  // berish mumkin, aks holda standart seed tartibiga (2) tayanamiz.
  final nishonId = int.tryParse(const String.fromEnvironment('OPERATOR_ID', defaultValue: '')) ?? (operatorId == 1 ? 2 : 2);

  final bekorQilishJavobi = await http.post(
    Uri.parse('$_backendUrl/foydalanuvchilar/$nishonId/tokenlarni-bekor-qilish'),
    headers: {'Authorization': 'Bearer $adminToken', 'Content-Type': 'application/json'},
    body: jsonEncode({'sabab': 'Real sinov: sessiya tugashi audit tuzatishi'}),
  );
  if (bekorQilishJavobi.statusCode != 200) {
    throw StateError('Token bekor qilish muvaffaqiyatsiz (${bekorQilishJavobi.statusCode}): ${bekorQilishJavobi.body}');
  }
  // ignore: avoid_print
  print('REAL SINOV: admin operator_a (id=$nishonId) tokenlarini HAQIQIY backend orqali bekor qildi.');
}

Future<void> _operatorSifatidaKirish(WidgetTester tester) async {
  await tester.tap(find.text('Operator'));
  await tester.pump();
  await tester.tap(find.text('A').first);
  await tester.pump();
  await tester.enterText(find.byType(TextField).first, _operatorParoli);
  await tester.pump();
  await tester.tap(find.text('Kirish'));
  await _kut(tester, marta: 8);
}

void main() {
  testWidgets(
    'REAL 1-STSENARIY: admin HAQIQIY backend orqali operator tokenini bekor qiladi -> "Saqlash" avtomatik login ekraniga qaytaradi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        ApiClient.bazaUrl = _backendUrl;

        await tester.pumpWidget(const KipTaroziApp());
        await _kut(tester, marta: 3);

        await _operatorSifatidaKirish(tester);
        expect(find.text('Tola'), findsWidgets, reason: 'Real backendga login qilib operator ekraniga o\'tishi kerak');

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 4);

        final partiyaRaqami = 900000 + DateTime.now().millisecondsSinceEpoch % 90000;
        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '$partiyaRaqami');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 5);

        // --- REAL: admin, HAQIQIY backend orqali, operatorning tokenini bekor qiladi ---
        await _adminOperatorTokeniniBekorQilsin();

        await tester.enterText(find.byType(TextField).last, '55.5');
        await tester.pump();
        await tester.tap(find.text('Saqlash'));
        await _kut(tester, marta: 8);

        expect(find.text('Operator'), findsOneWidget, reason: 'REAL 401dan keyin login ekraniga avtomatik qaytarilishi kerak');
        expect(
          find.textContaining('qaytadan kiring'),
          findsOneWidget,
          reason: '"Sessiyangiz tugadi" xabari ko\'rsatilishi kerak',
        );
      });
    },
  );

  testWidgets(
    'REAL 2-STSENARIY (ENG MUHIM): kamera-tasdiq bloklovchi dialogi ochiq bo\'lganda, admin HAQIQIY backend orqali tokenni bekor qiladi -> dialog avtomatik yopiladi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        ApiClient.bazaUrl = _backendUrl;

        await tester.pumpWidget(const KipTaroziApp());
        await _kut(tester, marta: 3);

        await _operatorSifatidaKirish(tester);
        expect(find.text('Tola'), findsWidgets);

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 4);

        final partiyaRaqami = 800000 + DateTime.now().millisecondsSinceEpoch % 90000;
        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '$partiyaRaqami');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 5);

        await tester.enterText(find.byType(TextField).last, '61.2');
        await tester.pump();
        await tester.tap(find.text('Saqlash'));
        // Backend haqiqiy KAMERA_TIMEOUT_SONIYA (~2s) davomida unreachable
        // kameraga ulanishga urinadi — shuning uchun bu yerda yetarlicha
        // uzoq (real vaqt) kutamiz.
        await _kut(tester, marta: 6, bosqich: const Duration(seconds: 1));

        // Backend'dagi KAMERA_IP unreachable bo'lgani uchun kip 202
        // (kamera_tasdiq_kutilmoqda) qaytarishi va bloklovchi dialog
        // ochilishi kerak (PopScope canPop:false).
        expect(find.byType(AlertDialog), findsOneWidget, reason: 'Real kamera-tasdiq kutish dialogi ochilishi kerak');

        // --- REAL: aynan shu daqiqada admin, HAQIQIY backend orqali,
        // operatorning tokenini bekor qiladi ---
        await _adminOperatorTokeniniBekorQilsin();

        // Poll (_kameraTasdiqPoll) har 3 soniyada — dialog yopilishini kutamiz.
        for (var i = 0; i < 12; i++) {
          await Future.delayed(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          if (find.byType(AlertDialog).evaluate().isEmpty) break;
        }

        expect(find.byType(AlertDialog), findsNothing, reason: 'REAL: bloklovchi dialog AVTOMATIK yopilishi kerak');
        expect(find.text('Operator'), findsOneWidget, reason: 'REAL: login ekraniga qaytarilishi kerak');
        expect(
          find.textContaining('qaytadan kiring'),
          findsOneWidget,
          reason: '"Sessiyangiz tugadi" xabari ko\'rsatilishi kerak',
        );
      });
    },
  );
}
