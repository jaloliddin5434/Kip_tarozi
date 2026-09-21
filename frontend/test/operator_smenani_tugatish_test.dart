// "Smenani tugatish" tugmasi (Operator ekrani, AppBar o'ng yuqori burchagi):
// 1) Dialog 4 mahsulotning bugungi soni/kg'sini (mavjud _smenaHolati'dan,
//    qo'shimcha backend so'rovisiz) to'g'ri ko'rsatishi.
// 2) Dialogdagi "X" bosilganda operator AVTOMATIK LOGOUT qilinib, login
//    (rol tanlash) ekraniga HAQIQATAN qaytarilishi.
//
// Mahalliy loopback HttpServer orqali soxta javoblar bilan, HAQIQIY
// backendga ulanmasdan sinaydi (qarang tasdiqlash_tarixi_test.dart bilan
// bir xil naqsh — to'liq KipTaroziApp, real login oqimi bilan).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';

Future<HttpServer> _soxtaServerYarat() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final yol = req.uri.path;
    dynamic tana;
    var status = 200;

    if (req.method == 'POST' && yol == '/api/v1/auth/login') {
      tana = {'access_token': 'sinov-tokeni'};
    } else if (yol == '/api/v1/auth/men') {
      tana = {'id': 1, 'ism': 'Sinov Operator', 'login': 'operator_a', 'rol': 'operator', 'smena': 'A'};
    } else if (yol == '/api/v1/mahsulotlar') {
      tana = [
        {'id': 1, 'kod': 'tola', 'nomi': 'Tola'},
        {'id': 2, 'kod': 'lint', 'nomi': 'Lint'},
        {'id': 3, 'kod': 'pux', 'nomi': 'Pux'},
        {'id': 4, 'kod': 'ulyuk', 'nomi': 'Ulyuk'},
      ];
    } else if (yol == '/api/v1/kiplar/smena/holati') {
      tana = {
        'smena': 'A',
        'sana': '2026-09-21',
        'mahsulotlar': [
          {'mahsulot_kodi': 'tola', 'mahsulot_nomi': 'Tola', 'soni': 3, 'jami_kg': 315.5},
          {'mahsulot_kodi': 'lint', 'mahsulot_nomi': 'Lint', 'soni': 1, 'jami_kg': 50.0},
          {'mahsulot_kodi': 'pux', 'mahsulot_nomi': 'Pux', 'soni': 0, 'jami_kg': 0.0},
          {'mahsulot_kodi': 'ulyuk', 'mahsulot_nomi': 'Ulyuk', 'soni': 0, 'jami_kg': 0.0},
        ],
      };
    } else if (yol == '/api/v1/kiplar/kamera-sozlamalari') {
      tana = {'agent_surat_url': null};
    } else if (yol == '/api/v1/kamera-tasdiq/mening-kutilayotganim') {
      tana = null;
    } else if (yol == '/api/v1/partiyalar/ochiq') {
      tana = [];
    } else if (yol == '/api/v1/kiplar/smena/royxat') {
      tana = [];
    } else {
      status = 404;
    }

    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(tana));
    await req.response.close();
  });
  return server;
}

Future<void> _kut(WidgetTester tester, {int marta = 10}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets(
    'Operator: "Smenani tugatish" dialogi to\'g\'ri soni/kg ko\'rsatadi, "X" avtomatik logout qiladi',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      late HttpServer server;

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = await _soxtaServerYarat();
        ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

        await tester.pumpWidget(const KipTaroziApp());
        await tester.pump();

        // --- Login: rol -> Operator, smena -> A, faqat parol maydoni ---
        await tester.tap(find.text('Operator'));
        await tester.pump();
        await tester.tap(find.text('A').first);
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'parolA');
        await tester.pump();
        await tester.tap(find.text('Kirish'));
        await _kut(tester, marta: 8);

        expect(find.text('Tola'), findsWidgets, reason: 'Operator ekraniga o\'tishi kerak');

        // --- "Smenani tugatish" tugmasini bosamiz ---
        await tester.tap(find.text('Smenani tugatish'));
        await _kut(tester, marta: 3);

        // Dialogda 4 mahsulotning soni/kg'si to'g'ri ko'rinishi kerak — orqadagi
        // "Bugungi smena ko'rsatkichi" kartalarida ham bir xil sonlar bo'lgani
        // uchun tekshiruvni AlertDialog ichiga scope qilamiz.
        Finder dialogIchida(String matn) =>
            find.descendant(of: find.byType(AlertDialog), matching: find.text(matn));

        expect(dialogIchida('3'), findsOneWidget, reason: 'Tola soni');
        expect(dialogIchida('315.5 kg'), findsOneWidget);
        expect(dialogIchida('1'), findsOneWidget, reason: 'Lint soni');
        expect(dialogIchida('50.0 kg'), findsOneWidget);
        // Pux/Ulyuk uchun soni=0 — ikkalasi ham "0" ko'rsatadi.
        expect(dialogIchida('0'), findsNWidgets(2));
        expect(dialogIchida('0.0 kg'), findsNWidgets(2));

        // --- "X" bosamiz -> avtomatik logout ---
        await tester.tap(find.byIcon(Icons.close));
        await _kut(tester, marta: 6);

        // Login (rol tanlash) ekraniga HAQIQATAN qaytarilgan — "Operator"/"Admin"
        // rol tugmalari yana ko'rinadi, Operator ekrani (mahsulot tugmalari) yo'q.
        expect(find.text('Operator'), findsOneWidget, reason: 'Rol tanlash ekraniga qaytishi kerak');
        expect(find.text('Smenani tugatish'), findsNothing);

        await server.close(force: true);
      });
    },
  );
}
