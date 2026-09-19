// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — qarang:
// operator_oqimi_test.dart izohi.
//
// AUDIT TUZATISHI (UX yangilash): "Shubhali holatlar" (anti-o'g'irlik)
// hodisasi ENDI operatorni BLOKLAMAYDI (ilgari bu test aynan qarama-qarshi —
// bloklovchi modal chiqishini — tekshirar edi). Endi bu test hodisani
// backendga to'g'ridan-to'g'ri (agent kaliti bilan) yozib, operator ekranida
// HECH QANDAY bloklovchi modal chiqmasligini VA oddiy kip saqlash odatdagidek
// ishlashini tasdiqlaydi. Hodisaning o'zi endi admin panelida
// ("Shubhali holatlar" ekrani, "Saqlash"/"Ko'rdim" tugmalari) hal qilinadi —
// qarang backend/tests/test_shubhali_holatlar.py.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _agentKey = String.fromEnvironment('AGENT_KEY', defaultValue: 'CHANGE_ME_AGENT_KEY');
// Login ekrani operator uchun loginni o'zi ('operator_a') hosil qiladi —
// faqat parol kerak. Real seedga mos parolni shu yerga qo'ying.
const _operatorParoli = String.fromEnvironment('OPERATOR_PAROLI', defaultValue: 'smenaA123');

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
  testWidgets('Yuk saqlanmadi: hodisa yaratilsa ham operator ENDI bloklanmaydi, kip odatdagidek saqlanadi', (
    tester,
  ) async {
    ApiClient.bazaUrl = _backendUrl;
    SharedPreferences.setMockInitialValues({});

    await tester.runAsync(() async {
      HttpOverrides.global = null;

      await _shubhaliHodisaYarat();

      await tester.pumpWidget(const KipTaroziApp());
      await _tarmoqniKut(tester, marta: 3);

      // Login ekrani avval ROL, so'ng (operator uchun) SMENA tanlashni
      // talab qiladi; login shundan o'zi hosil bo'ladi (operator_a) —
      // faqat parol maydoni qoladi.
      await tester.tap(find.text('Operator'));
      await tester.pump();
      await tester.tap(find.text('A').first);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, _operatorParoli);
      await tester.pump();
      await tester.tap(find.text('Kirish'));
      await _tarmoqniKut(tester);

      expect(find.text('Tola'), findsOneWidget, reason: 'Operator ekraniga to\'g\'ridan-to\'g\'ri o\'tishi kerak');

      // Blok-tekshiruvchi Timer avvalgi 5s oralig'ida ishlar edi — endi
      // shubhali-holat uchun HECH NARSA tekshirmaydi, lekin shuncha vaqt
      // kutib, HECH QANDAY bloklovchi modal chiqmasligini tasdiqlaymiz.
      await _tarmoqniKut(tester, marta: 30); // ~6 soniya real vaqt

      expect(find.byType(AlertDialog), findsNothing, reason: 'Hech qanday bloklovchi modal chiqmasligi kerak');
      expect(find.text('Tola'), findsOneWidget, reason: 'Operator ekrani hali ham normal ishlatilishi mumkin');

      // --- Oddiy kip saqlash oqimi ODATDAGIDEK ishlashini tasdiqlaymiz ---
      await tester.tap(find.text('Tola'));
      await _tarmoqniKut(tester, marta: 4);

      final partiyaRaqami = 800000 + DateTime.now().millisecondsSinceEpoch % 90000;
      final partiyaMaydoni = find.widgetWithText(TextField, 'Partiya raqami');
      await tester.ensureVisible(partiyaMaydoni);
      await tester.enterText(partiyaMaydoni, '$partiyaRaqami');
      await tester.pump();

      final ochishTugmasi = find.text('Partiyani tanlash');
      await tester.ensureVisible(ochishTugmasi);
      await tester.tap(ochishTugmasi);
      await _tarmoqniKut(tester, marta: 6);

      expect(find.textContaining('#$partiyaRaqami'), findsWidgets, reason: 'Partiya ochilgan bo\'lishi kerak');

      final ogirlikMaydoni = find.widgetWithText(TextField, "Og'irlik (kg)");
      await tester.ensureVisible(ogirlikMaydoni);
      await tester.enterText(ogirlikMaydoni, '112.0');
      await tester.pump();

      final saqlashTugmasi = find.text('Saqlash');
      await tester.ensureVisible(saqlashTugmasi);
      await tester.tap(saqlashTugmasi);
      await _tarmoqniKut(tester, marta: 6);

      expect(
        find.text('Kip saqlandi'),
        findsOneWidget,
        reason: 'Hal qilinmagan shubhali holat bo\'lsa ham kip ODATDAGIDEK saqlanishi kerak (409 YO\'Q)',
      );
    });
  });
}
