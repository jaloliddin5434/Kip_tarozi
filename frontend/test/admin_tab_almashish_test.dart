// admin_shell.dart'dagi Expanded->IndexedStack tuzatishini sinaydi: bo'limlar
// orasida TEZ almashtirilganda (hali oldingi so'rov "havoda" turgan paytda)
// hech qanday "setState() called after dispose()" yoki boshqa FlutterError
// chiqmasligini tasdiqlaydi.
//
// Haqiqiy backendga (va demak haqiqiy bazaga) ULANMAYDI — bu yerda mahalliy
// loopback HttpServer orqali soxta (lekin har bir ekran kutgan aniq shaklga
// mos) javoblar qaytariladi, har biriga QASDDAN kechikish qo'shilgan — bu
// aynan avval xato bergan "sekin javob" ssenariysini takrorlaydi, real
// tarmoq/baza tezligiga bog'liq bo'lmagan holda.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

const _bolimlar = [
  'Bosh sahifa',
  'Hujjatlar',
  'Statistika',
  'Partiyalar',
  'Shubhali holatlar',
  'Moliyaviy',
  'Sozlamalar',
];

const _sekinlashuv = Duration(milliseconds: 600);

Future<HttpServer> _soxtaServerYarat() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    await Future.delayed(_sekinlashuv);
    final yol = req.uri.path;
    dynamic tana;

    if (req.method == 'POST' && yol == '/api/v1/auth/login') {
      tana = {'access_token': 'sinov-tokeni'};
    } else if (yol == '/api/v1/auth/men') {
      tana = {'id': 1, 'ism': 'Sinov Admin', 'login': 'admin', 'rol': 'admin', 'smena': null};
    } else if (yol == '/api/v1/dashboard') {
      tana = {
        'davr': 'kunlik',
        'boshlanish_sanasi': '2026-09-01',
        'tugash_sanasi': '2026-09-06',
        'mahsulotlar': [],
        'jami_soni': 0,
        'jami_kg': 0.0,
        'smenalar': [],
        'ochiq_partiyalar_soni': 0,
        'tasdiqlanmagan_shubhali_holatlar_soni': 0,
        'agent_holati': null,
      };
    } else if (yol == '/api/v1/hujjatlar/kiplar') {
      tana = {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 50};
    } else if (yol == '/api/v1/statistika/jamlanma') {
      tana = {
        'davr': 'kunlik',
        'boshlanish_sanasi': '2026-09-01',
        'tugash_sanasi': '2026-09-06',
        'mahsulotlar': [],
        'jami_soni': 0,
        'jami_kg': 0.0,
      };
    } else if (yol == '/api/v1/statistika/smena-boyicha') {
      tana = [];
    } else if (yol == '/api/v1/partiyalar') {
      tana = {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 100};
    } else if (yol == '/api/v1/shubhali-holatlar') {
      tana = {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 50};
    } else if (yol == '/api/v1/shubhali-holatlar/statistika') {
      tana = {'smena_boyicha': <String, int>{}, 'operator_boyicha': []};
    } else if (yol == '/api/v1/sozlamalar') {
      tana = [];
    } else {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }

    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(tana));
    await req.response.close();
  });
  return server;
}

Future<void> _tarmoqniKut(WidgetTester tester, {int marta = 10}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Admin: bo\'limlar orasida tez almashtirish — dispose xatosi chiqmasligi kerak', (tester) async {
    // Standart test ekrani (800x600) ba'zi ekranlarda RenderFlex overflow
    // ogohlantirishi berdi — bu haqiqiy desktop oynasida kuzatilmaydigan,
    // faqat test yuzasi torligidan kelib chiqadigan alohida (dispose bilan
    // bog'liq bo'lmagan) muammo, shuning uchun kattaroq yuzaga o'rnatamiz.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});

    final xatolar = <FlutterErrorDetails>[];
    final eskiOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      xatolar.add(details);
      eskiOnError?.call(details);
    };

    late HttpServer server;

    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await _soxtaServerYarat();
      ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

      await tester.pumpWidget(const KipTaroziApp());
      await tester.pump();

      await tester.tap(find.text('Admin'));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'admin');
      await tester.enterText(find.byType(TextField).at(1), 'admin12345');
      await tester.pump();
      await tester.tap(find.text('Kirish'));
      // Login davomida ikkita so'rov (login + men) ham qasddan sekinlashtirilgan.
      await _tarmoqniKut(tester, marta: 8);

      expect(find.text('Bosh sahifa'), findsOneWidget, reason: 'Admin panel navigatsiyasi ko\'rinishi kerak');

      // AdminShell IndexedStack ishlatgani uchun BARCHA 7 ekran darhol
      // mount bo'ladi va initState()'lari darhol o'zining _yuklash()'ini
      // chaqiradi — hammasi hozir soxta serverdan sekin javob kutmoqda.
      // Aynan shu payt, javoblar hali qaytmasdan turib, bo'limlar orasida
      // tez-tez almashtiramiz.
      for (var aylanish = 0; aylanish < 3; aylanish++) {
        for (final nomi in _bolimlar) {
          final topilma = find.text(nomi);
          await tester.ensureVisible(topilma);
          await tester.tap(topilma);
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      // Endi hamma "havoda" turgan so'rovlar javob qaytarishi uchun
      // yetarlicha kutamiz — aynan shu yerda, eski kodda, dispose qilingan
      // State'ga setState() chaqirilib xato berardi.
      await _tarmoqniKut(tester, marta: 10);

      // Yana bir bor, har bir bo'limda birma-bir to'xtab chiqamiz.
      for (final nomi in _bolimlar) {
        final topilma = find.text(nomi);
        await tester.ensureVisible(topilma);
        await tester.tap(topilma);
        await _tarmoqniKut(tester, marta: 5);
      }

      await server.close(force: true);
    });

    FlutterError.onError = eskiOnError;

    expect(xatolar, isEmpty, reason: 'Bo\'limlar almashtirilganda FlutterError chiqmasligi kerak: $xatolar');
  });
}
