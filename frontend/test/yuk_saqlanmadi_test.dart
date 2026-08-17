// Haqiqiy backendga ulanadi — qarang: operator_oqimi_test.dart izohi.
// Bu test anti-o'g'irlik hodisasini backendga to'g'ridan-to'g'ri (agent kaliti
// bilan) yozadi va operator ekranidagi bloklovchi modal 5s polling orqali
// avtomatik chiqishini, "Tushundim" bosgach yopilishini tekshiradi.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _agentKey = String.fromEnvironment('AGENT_KEY', defaultValue: 'CHANGE_ME_AGENT_KEY');

Future<void> _tarmoqniKut(WidgetTester tester, {int marta = 10}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _shubhaliHodisaYarat() async {
  final sorov = http.MultipartRequest('POST', Uri.parse('$_backendUrl/shubhali-holatlar'))
    ..headers['X-Agent-Key'] = _agentKey
    ..fields['ogirlik'] = '140.0'
    ..fields['vaqt'] = DateTime.now().toUtc().toIso8601String()
    ..fields['smena'] = 'A';
  final javob = await http.Response.fromStream(await sorov.send());
  if (javob.statusCode >= 300) {
    throw Exception('Shubhali holat yaratib bo\'lmadi: ${javob.statusCode} ${javob.body}');
  }
}

void main() {
  testWidgets('Yuk saqlanmadi: bloklovchi modal chiqadi va Tushundim bilan yopiladi', (tester) async {
    ApiClient.bazaUrl = _backendUrl;
    SharedPreferences.setMockInitialValues({});

    await tester.runAsync(() async {
      HttpOverrides.global = null;

      await _shubhaliHodisaYarat();

      await tester.pumpWidget(const KipTaroziApp());
      await _tarmoqniKut(tester, marta: 3);

      await tester.enterText(find.byType(TextField).first, 'smena_a');
      await tester.enterText(find.byType(TextField).at(1), 'smenaA123');
      await tester.pump();
      await tester.tap(find.text('Kirish'));
      await _tarmoqniKut(tester);

      // Blok-tekshiruvchi Timer 5s oralig'ida ishlaydi — shuncha kutamiz
      await _tarmoqniKut(tester, marta: 30); // ~6 soniya real vaqt

      expect(find.text('⚠️ YUK SAQLANMADI!'), findsOneWidget, reason: 'Bloklovchi modal avtomatik chiqishi kerak');

      // Saqlash tugmasi hali ham ekranda, lekin modal uni bloklaydi (PopScope + barrier)
      await tester.tap(find.text('Tushundim'));
      await _tarmoqniKut(tester, marta: 6);

      expect(find.text('⚠️ YUK SAQLANMADI!'), findsNothing, reason: 'Tushundim bosilgach modal yopilishi kerak');
    });
  });
}
