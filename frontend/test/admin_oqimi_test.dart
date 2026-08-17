// Haqiqiy backendga ulanadi — qarang: operator_oqimi_test.dart izohi.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');

Future<void> _tarmoqniKut(WidgetTester tester, {int marta = 10}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Admin: kirish -> Dashboard -> Hujjatlar', (tester) async {
    ApiClient.bazaUrl = _backendUrl;
    SharedPreferences.setMockInitialValues({});

    await tester.runAsync(() async {
      HttpOverrides.global = null;

      await tester.pumpWidget(const KipTaroziApp());
      await _tarmoqniKut(tester, marta: 3);

      await tester.enterText(find.byType(TextField).first, 'admin');
      await tester.enterText(find.byType(TextField).at(1), 'admin12345');
      await tester.pump();
      await tester.tap(find.text('Kirish'));
      await _tarmoqniKut(tester);

      expect(find.text('Bosh sahifa'), findsOneWidget, reason: 'Admin panel navigatsiyasi ko\'rinishi kerak');
      expect(find.text('Ochiq partiyalar'), findsOneWidget, reason: 'Dashboard statistika kartalari ko\'rinishi kerak');

      await tester.tap(find.text('Hujjatlar'));
      await _tarmoqniKut(tester, marta: 4);

      expect(find.byType(DataTable), findsOneWidget, reason: 'Hujjatlar jadvali ko\'rinishi kerak');

      final shubhaliTab = find.text('Shubhali holatlar');
      await tester.ensureVisible(shubhaliTab);
      await tester.tap(shubhaliTab);
      await _tarmoqniKut(tester, marta: 4);

      // Aniq sonni emas, ekran to'g'ri render bo'lganini (filtr chiplari +
      // "Jami" statistikasi ko'rinishini) tekshiramiz — boshqa testlar
      // parallel/ketma-ket hodisa yozishi mumkin, son barqaror emas.
      expect(find.text('A'), findsWidgets, reason: 'Smena filtr chiplari ko\'rinishi kerak');
      expect(find.textContaining('Jami:'), findsOneWidget, reason: 'Jami statistikasi ko\'rinishi kerak');
    });
  });
}
