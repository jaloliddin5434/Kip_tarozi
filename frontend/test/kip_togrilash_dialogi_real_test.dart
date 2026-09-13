// Bu test HAQIQIY, jonli backendga ulanadi (mock emas) — qarang:
// operator_oqimi_test.dart izohi (bir xil naqsh). AUDIT TUZATISHI (UX):
// kip_togrilash_dialogi.dart'dagi "Partiya raqami" maydonini REAL operator
// ekrani + REAL backend orqali, boshidan oxirigacha (mahsulot tanlash ->
// partiyalar ochish -> kip saqlash -> "Smena tarixi"dan to'g'irlash
// dialogini ochish -> ochiq partiyalar ro'yxatini ko'rish -> mahsulot
// almashtirib ro'yxat yangilanishini ko'rish -> qo'lda raqam kiritish ->
// yuborish) tasdiqlaydi.
//
// Ishga tushirish:
//   1. Ajratilgan test bazasida migratsiya bajarilgan, operator_a
//      (login "operator_a"/smenaA123) mavjud bo'lsin. Kamera O'CHIRILGAN
//      (KAMERA_IP="") bo'lsin — oddiy saqlash to'g'ridan-to'g'ri ishlasin.
//   2. uvicorn app.main:app --port 8010 shu bazaga ulangan holda ishlasin.
//   3. flutter test test/kip_togrilash_dialogi_real_test.dart --dart-define=BACKEND_URL=http://localhost:8010/api/v1

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _backendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8010/api/v1');
const _operatorParoli = String.fromEnvironment('OPERATOR_PAROLI', defaultValue: 'smenaA123');

/// Dialog ORTIDA turgan operator ekranida ham xuddi shunday matnli
/// (masalan "#501") chiplar bo'lishi mumkin — shuning uchun har doim
/// FAQAT dialog ICHIDA qidiramiz.
Finder _dialogda(String matnBolagi) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.textContaining(matnBolagi));

/// Operator ekranining o'zida ham xuddi shu labelli ("Partiya raqami")
/// TextField bor — shuning uchun har doim FAQAT dialog ICHIDAGISINI olamiz.
Finder get _dialogPartiyaMaydoni =>
    find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextField, 'Partiya raqami'));

Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

/// Berilgan mahsulot tanlab, berilgan raqamli partiyani ochadi (yangi
/// bo'lsa yaratiladi, mavjud bo'lsa shunchaki tanlanadi) — real operator
/// ekrani orqali.
Future<void> _mahsulotTanlabPartiyaOchish(WidgetTester tester, String mahsulotNomi, int raqam) async {
  await tester.tap(find.text(mahsulotNomi).first);
  await _kut(tester, marta: 4);
  await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '$raqam');
  await tester.tap(find.text('Partiyani tanlash'));
  await _kut(tester, marta: 4);
}

void main() {
  testWidgets(
    'REAL: "Smena tarixi"dan to\'g\'irlash dialogi ochiladi, ochiq partiyalar ro\'yxati ko\'rinadi, mahsulot almashtirilsa yangilanadi, qo\'lda raqam kiritish ishlaydi',
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

        // --- Real login ---
        await tester.tap(find.text('Operator'));
        await tester.pump();
        await tester.tap(find.text('A').first);
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, _operatorParoli);
        await tester.pump();
        await tester.tap(find.text('Kirish'));
        await _kut(tester, marta: 8);

        final tolaRaqami1 = 500000 + DateTime.now().millisecondsSinceEpoch % 90000;
        final tolaRaqami2 = tolaRaqami1 + 1;
        final lintRaqami = tolaRaqami1 + 2;

        // --- Tola: birinchi partiyani ochib, HAQIQIY kip saqlaymiz ---
        await _mahsulotTanlabPartiyaOchish(tester, 'Tola', tolaRaqami1);
        await tester.enterText(find.byType(TextField).last, '50.0');
        await tester.pump();
        await tester.tap(find.text('Saqlash'));
        await _kut(tester, marta: 6);
        expect(find.text('Kip saqlandi'), findsOneWidget, reason: 'Real kip saqlanishi kerak');

        // --- Tola: ikkinchi (bo'sh) partiyani ham ochamiz — endi Tola
        // uchun IKKITA ochiq partiya bo'ladi ---
        await _mahsulotTanlabPartiyaOchish(tester, 'Tola', tolaRaqami2);

        // --- Lint uchun ham bitta ochiq partiya ochamiz ---
        await _mahsulotTanlabPartiyaOchish(tester, 'Lint', lintRaqami);

        // --- Tolaga qaytamiz — "Smena tarixi"da saqlangan kipni ko'ramiz ---
        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 4);
        expect(find.textContaining('50.0 kg'), findsWidgets, reason: 'Smena tarixida saqlangan kip ko\'rinishi kerak');

        // --- To'g'irlash dialogini ochamiz ---
        // `.first` — bir necha marta ishga tushirilsa (bir xil kunlik
        // smena tarixida oldingi urinishlardan qolgan kiplar bo'lsa ham)
        // qaysi qatorni tanlashi muhim emas, dialog xatti-harakati bir xil.
        final tahrirBelgisi = find.byIcon(Icons.edit_outlined).first;
        await tester.ensureVisible(tahrirBelgisi);
        await tester.tap(tahrirBelgisi);
        await _kut(tester, marta: 4);
        // Sarlavha "Kipni to'g'rilash — №<raqam>" ko'rinishida (kip
        // raqami bilan birga) — shuning uchun to'liq emas, qisman qidiramiz.
        expect(find.textContaining('Kipni to\'g\'rilash'), findsOneWidget, reason: 'To\'g\'irlash dialogi ochilishi kerak');

        // --- Dialog ichida "Tola"ni tanlaymiz — real backend orqali ochiq
        // partiyalar (ikkalasi ham) chip qilib ko'rinishi kerak ---
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Tola')));
        await _kut(tester, marta: 5);
        expect(_dialogda('#$tolaRaqami1'), findsOneWidget, reason: 'Birinchi ochiq Tola partiyasi ko\'rinishi kerak');
        expect(_dialogda('#$tolaRaqami2'), findsOneWidget, reason: 'Ikkinchi ochiq Tola partiyasi ko\'rinishi kerak');

        // Chipni bosib tanlaymiz.
        await tester.tap(_dialogda('#$tolaRaqami2'));
        await tester.pump();
        final tolaTanlangach = tester.widget<TextField>(_dialogPartiyaMaydoni);
        expect(tolaTanlangach.controller!.text, '$tolaRaqami2');

        // --- Mahsulotni "Lint"ga almashtiramiz — ro'yxat yangilanishi kerak ---
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Lint')));
        await _kut(tester, marta: 5);
        expect(_dialogda('#$tolaRaqami1'), findsNothing, reason: 'Eski (Tola) partiyalar endi ko\'rinmasligi kerak');
        expect(_dialogda('#$tolaRaqami2'), findsNothing);
        expect(_dialogda('#$lintRaqami'), findsOneWidget, reason: 'Lint uchun ochiq partiya ko\'rinishi kerak');
        final lintTanlangach = tester.widget<TextField>(_dialogPartiyaMaydoni);
        expect(lintTanlangach.controller!.text, '', reason: 'Mahsulot almashtirilganda partiya raqami tozalanishi kerak');

        // --- Ro'yxatda YO'Q raqamni qo'lda (faqat raqam) kiritamiz ---
        final yangiRaqam = lintRaqami + 500;
        await tester.enterText(_dialogPartiyaMaydoni, 'a${yangiRaqam}b');
        await tester.pump();
        final qolDaKiritilgan = tester.widget<TextField>(_dialogPartiyaMaydoni);
        expect(qolDaKiritilgan.controller!.text, '$yangiRaqam', reason: 'Harflar filtrlanib, faqat raqam qolishi kerak');

        // Bu raqam ochiq emas (real backendda mavjud emas) — shuning uchun
        // haqiqiy yuborishda 400 "Partiya topilmadi" kutiladi; buni ATAYLAB
        // haqiqiy (mavjud) Lint partiyasi bilan almashtirib, TO'LIQ
        // muvaffaqiyatli yuborishni ham tasdiqlaymiz.
        await tester.tap(_dialogda('#$lintRaqami'));
        await tester.pump();

        await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).last,
          'Real sinov: operator noto\'g\'ri mahsulot tanlagan',
        );
        await tester.pump();
        await tester.tap(find.text('Zayavka yuborish'));
        await _kut(tester, marta: 6);

        expect(
          find.textContaining('yuborildi'),
          findsOneWidget,
          reason: 'REAL: to\'g\'irlash zayavkasi muvaffaqiyatli yuborilgani haqida xabar ko\'rinishi kerak',
        );
      });
    },
  );
}
