// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — qarang:
// operator_oqimi_test.dart izohi (bir xil naqsh). AUDIT TUZATISHI: Enter
// orqali "band" holatni chetlab o'tish mumkin bo'lgan ikkita joyni REAL
// backend bilan tasdiqlaydi (mos, tezkor soxta-server versiyasi —
// enter_double_submit_test.dart).
//
// Ishga tushirish:
//   1. Ajratilgan test bazasida migratsiya bajarilgan, operator_a
//      (login "operator_a"/smenaA123) mavjud bo'lsin.
//   2. uvicorn app.main:app --port 8010 shu bazaga ulangan holda ishlasin
//      (log fayliga yozib turadigan holda — POST /auth/login sonini shu
//      logdan hisoblaymiz).
//   3. flutter test test/enter_double_submit_real_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1 --dart-define=BACKEND_LOG=/tmp_es_backend.log

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _operatorParoli = String.fromEnvironment('OPERATOR_PAROLI', defaultValue: 'smenaA123');
const _backendLogYoli = String.fromEnvironment('BACKEND_LOG', defaultValue: '');

Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

int _loginPostSoni() {
  if (_backendLogYoli.isEmpty) return -1;
  final fayl = File(_backendLogYoli);
  if (!fayl.existsSync()) return -1;
  final matn = fayl.readAsStringSync();
  return RegExp(r'POST /api/v1/auth/login').allMatches(matn).length;
}

void main() {
  testWidgets(
    'REAL 1-STSENARIY: og\'irlik maydonida Enter — Saqlashdan keyingi 3s sovish davrida qayta chaqirilmaydi (haqiqiy kip soni o\'zgarmaydi)',
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

        await tester.tap(find.text('Operator'));
        await tester.pump();
        await tester.tap(find.text('A').first);
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, _operatorParoli);
        await tester.pump();
        await tester.tap(find.text('Kirish'));
        await _kut(tester, marta: 8);

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 4);

        final partiyaRaqami = 700000 + DateTime.now().millisecondsSinceEpoch % 90000;
        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '$partiyaRaqami');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 5);

        final ogirlikMaydoni = find.byType(TextField).last;
        await tester.enterText(ogirlikMaydoni, '123.4');
        await tester.pump();
        await tester.tap(find.text('Saqlash'));
        await _kut(tester, marta: 6);

        expect(find.text('Kip saqlandi'), findsOneWidget, reason: 'Birinchi saqlash muvaffaqiyatli bo\'lishi kerak');

        // --- REAL: 3s sovish davri ICHIDA, bo'sh og'irlik maydonida Enter ---
        await tester.showKeyboard(ogirlikMaydoni);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _kut(tester, marta: 5);

        expect(
          find.textContaining('kiriting'),
          findsNothing,
          reason: 'REAL: sovish davrida Enter bosilsa hech qanday chalg\'ituvchi xato chiqmasligi kerak',
        );

        // Partiya progress-panelida ko'rinadigan kip-soni HALI HAM 1 —
        // Enter ikkinchi kipni yaratmagan (backend real POST /kiplar
        // qabul qilmagan, aks holda "1/220" o'rniga "2/220" ko'rinardi).
        expect(
          find.textContaining('#$partiyaRaqami (1/220)'),
          findsOneWidget,
          reason: 'REAL: partiyada faqat 1 ta kip qolishi kerak (ikkinchi POST ketmagan)',
        );
      });
    },
  );

  testWidgets(
    'REAL 2-STSENARIY: parol maydonida tez-tez Enter — backend logida FAQAT bitta POST /auth/login qatori qo\'shiladi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      final boshlanishdaSoni = _loginPostSoni();

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        ApiClient.bazaUrl = _backendUrl;

        await tester.pumpWidget(const KipTaroziApp());
        await tester.pump();

        await tester.tap(find.text('Operator'));
        await tester.pump();
        await tester.tap(find.text('A').first);
        await tester.pump();

        final parolMaydoni = find.byType(TextField).first;
        await tester.enterText(parolMaydoni, _operatorParoli);
        await tester.pump();

        await tester.showKeyboard(parolMaydoni);
        for (var i = 0; i < 6; i++) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump(const Duration(milliseconds: 15));
        }

        await _kut(tester, marta: 10);
      });

      if (_backendLogYoli.isNotEmpty) {
        final oxiridagiSoni = _loginPostSoni();
        // ignore: avoid_print
        print('REAL SINOV: backend logida POST /auth/login soni: $boshlanishdaSoni -> $oxiridagiSoni');
        expect(
          oxiridagiSoni - boshlanishdaSoni,
          1,
          reason: 'REAL: tez-tez Enter bosilsa ham backend logida FAQAT bitta yangi POST /auth/login qatori bo\'lishi kerak',
        );
      }
    },
  );
}
