// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — CI'da emas, faqat
// dev vaqtida `flutter test test/operator_oqimi_test.dart` bilan qo'lda
// ishga tushiriladi, chunki backend server va Postgres kerak.
//
// Ishga tushirish:
//   1. backend/.env'da bazaga ulanish sozlangan bo'lsin, migratsiya bajarilgan,
//      seed orqali smena_a/smenaA123 operatori yaratilgan bo'lsin.
//   2. uvicorn app.main:app --port 8010 ishga tushirilgan bo'lsin.
//   3. flutter test test/operator_oqimi_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');

/// Haqiqiy tarmoq javobini kutish uchun — pump() yolg'iz o'zi real IO
/// bilan sinxronlanmaydi, shuning uchun real vaqt kechikishi bilan
/// birga bir necha marta pump qilamiz.
Future<void> _tarmoqniKut(WidgetTester tester, {int marta = 10}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Operator: kirish -> partiya ochish -> kip saqlash', (tester) async {
    ApiClient.bazaUrl = _backendUrl;
    SharedPreferences.setMockInitialValues({});

    await tester.runAsync(() async {
      // flutter test standart holatda haqiqiy HTTP so'rovlarini bloklaydi — bu
      // testga xos, real backendga ulanish uchun ochib qo'yiladi.
      HttpOverrides.global = null;

      await tester.pumpWidget(const KipTaroziApp());
      await _tarmoqniKut(tester, marta: 3);

      // --- Login ---
      final loginMaydoni = find.byType(TextField).first;
      final parolMaydoni = find.byType(TextField).at(1);
      await tester.enterText(loginMaydoni, 'smena_a');
      await tester.enterText(parolMaydoni, 'smenaA123');
      await tester.pump();

      await tester.tap(find.text('Kirish'));
      await _tarmoqniKut(tester);

      _agarTopilmasaMatnlarniChiqar(find.text('Tola'), 'login\'dan keyin');
      expect(find.text('Tola'), findsOneWidget, reason: 'Operator ekraniga o\'tishi va mahsulot tugmalari ko\'rinishi kerak');

      // --- Mahsulot tanlash ---
      await tester.tap(find.text('Tola'));
      await _tarmoqniKut(tester, marta: 4);

      // --- Partiya ochish ---
      final partiyaRaqamiTest = DateTime.now().millisecondsSinceEpoch % 100000;
      final partiyaRaqamiMaydoni = find.widgetWithText(TextField, 'Partiya raqami');
      await tester.ensureVisible(partiyaRaqamiMaydoni);
      await tester.enterText(partiyaRaqamiMaydoni, '$partiyaRaqamiTest');
      await tester.pump();

      final ochishTugmasi = find.text('Partiyani tanlash');
      await tester.ensureVisible(ochishTugmasi);
      await tester.tap(ochishTugmasi);
      await _tarmoqniKut(tester, marta: 6);

      _agarTopilmasaMatnlarniChiqar(find.textContaining('#$partiyaRaqamiTest'), 'partiya ochilgandan keyin');
      expect(find.textContaining('#$partiyaRaqamiTest'), findsWidgets, reason: 'Ochilgan partiya raqami ekranda ko\'rinishi kerak');

      // --- Kip saqlash ---
      final ogirlikMaydoni = find.widgetWithText(TextField, "Og'irlik (kg)");
      await tester.ensureVisible(ogirlikMaydoni);
      await tester.enterText(ogirlikMaydoni, '135.5');
      await tester.pump();

      final saqlashTugmasi = find.text('Saqlash');
      await tester.ensureVisible(saqlashTugmasi);
      await tester.tap(saqlashTugmasi);
      await _tarmoqniKut(tester, marta: 6);

      _agarTopilmasaMatnlarniChiqar(find.text('Kip saqlandi'), 'kip saqlangandan keyin');
      expect(find.text('Kip saqlandi'), findsOneWidget, reason: 'Saqlangach snackbar ko\'rinishi kerak');
      expect(find.textContaining('Bekor qilish'), findsWidgets, reason: '30s tezkor bekor qilish tugmasi ko\'rinishi kerak');
    });
  });
}

void _agarTopilmasaMatnlarniChiqar(Finder finder, String bosqich) {
  if (finder.evaluate().isEmpty) {
    final matnlar = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList();
    // ignore: avoid_print
    print('DEBUG [$bosqich] joriy matnlar: $matnlar');
  }
}
