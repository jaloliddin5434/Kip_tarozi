// "Tasdiqlash tarixi" (Kamera tasdiqlari + Kip to'g'irlash so'rovlarini
// birlashtirgan admin ekrani) — mahalliy loopback HttpServer orqali soxta
// javoblar bilan, HAQIQIY backendga ulanmasdan sinaydi (tez, CI-xavfsiz;
// qarang admin_tab_almashish_test.dart bilan bir xil naqsh).
//
// Ikkita narsani tekshiradi:
// 1) Asosiy ro'yxatda IKKALA tur (kamera, kip_togrilash) "Turi" ustunida
//    to'g'ri chiplar va tavsif/sabab bilan ko'rinishi.
// 2) Kalendarda "bugun"ga bosilganda `hal_qilingan_sana` so'rovi yuborilib,
//    o'sha kunda hal qilingan (tasdiqlangan + rad etilgan) yozuvlar
//    tafsilot panelida turi/operator/tavsif/sabab/izoh/kim-hal-qildi bilan
//    to'g'ri ko'rsatilishi.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';
import 'package:kip_tarozi/widgets/kalendar_vidjeti.dart';

final _bugun = DateTime.now();

Map<String, dynamic> _yozuv({
  required String tur,
  required int id,
  required String tavsif,
  String? sabab,
  required String holati,
  String? halQilinganVaqt,
  String? halQilganIsm,
  String? izoh,
}) => {
  'tur': tur,
  'id': id,
  'vaqt': DateTime.now().toUtc().toIso8601String(),
  'operator_ism': 'Operator Test',
  'tavsif': tavsif,
  'sabab': sabab,
  'holati': holati,
  'hal_qilingan_vaqt': halQilinganVaqt,
  'hal_qilgan_ism': halQilganIsm,
  'hal_qilish_manbasi': halQilganIsm == null ? null : 'panel',
  'izoh': izoh,
  'dublikat_shubhasi': false,
};

Future<HttpServer> _soxtaServerYarat() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final yol = req.uri.path;
    dynamic tana;
    var status = 200;

    if (req.method == 'POST' && yol == '/api/v1/auth/login') {
      tana = {'access_token': 'sinov-tokeni'};
    } else if (yol == '/api/v1/auth/men') {
      tana = {'id': 1, 'ism': 'Sinov Admin', 'login': 'admin', 'rol': 'admin', 'smena': null};
    } else if (yol == '/api/v1/dashboard') {
      tana = {
        'davr': 'kunlik', 'boshlanish_sanasi': '2026-09-01', 'tugash_sanasi': '2026-09-06',
        'mahsulotlar': [], 'jami_soni': 0, 'jami_kg': 0.0, 'smenalar': [],
        'ochiq_partiyalar_soni': 0, 'tasdiqlanmagan_shubhali_holatlar_soni': 0, 'agent_holati': null,
      };
    } else if (yol == '/api/v1/hujjatlar/kiplar') {
      tana = {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 50};
    } else if (yol == '/api/v1/statistika/jamlanma') {
      tana = {
        'davr': 'kunlik', 'boshlanish_sanasi': '2026-09-01', 'tugash_sanasi': '2026-09-06',
        'mahsulotlar': [], 'jami_soni': 0, 'jami_kg': 0.0,
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
    } else if (yol == '/api/v1/tasdiqlash-tarixi') {
      if (req.uri.queryParameters.containsKey('hal_qilingan_sana')) {
        // Kalendar kun-tafsiloti: o'sha kunda hal qilingan ikkala tur ham.
        tana = {
          'items': [
            _yozuv(
              tur: 'kamera', id: 3, tavsif: 'Lint #900, 88.0 kg',
              holati: 'tasdiqlangan', halQilinganVaqt: DateTime.now().toUtc().toIso8601String(),
              halQilganIsm: 'Sinov Admin',
            ),
            _yozuv(
              tur: 'kip_togrilash', id: 4, tavsif: 'Kip №9: Tola #700 -> Lint #701',
              sabab: 'Operator xato tanlagan', holati: 'rad_etilgan',
              halQilinganVaqt: DateTime.now().toUtc().toIso8601String(),
              halQilganIsm: 'Sinov Admin', izoh: 'Kip allaqachon hisobga olingan',
            ),
          ],
          'jami': 2, 'sahifa': 1, 'sahifa_hajmi': 500,
        };
      } else {
        // Asosiy (standart: faqat "kutilmoqda") ro'yxat — ikkala tur ham bor.
        tana = {
          'items': [
            _yozuv(tur: 'kamera', id: 1, tavsif: 'Tola #501, 105.3 kg', holati: 'kutilmoqda'),
            _yozuv(
              tur: 'kip_togrilash', id: 2, tavsif: 'Kip №7: Tola #501 -> Lint #502',
              sabab: 'Xato tanlandi', holati: 'kutilmoqda',
            ),
          ],
          'jami': 2, 'sahifa': 1, 'sahifa_hajmi': 30,
        };
      }
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
    'Tasdiqlash tarixi: birlashtirilgan ro\'yxatda ikkala tur + kalendar kun-tafsiloti',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
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

        await tester.tap(find.text('Admin'));
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'admin');
        await tester.enterText(find.byType(TextField).at(1), 'admin12345');
        await tester.pump();
        await tester.tap(find.text('Kirish'));
        await _kut(tester, marta: 8);

        // --- Yangi birlashtirilgan nav bandiga o'tamiz ---
        final navBandi = find.text('Tasdiqlash tarixi');
        expect(navBandi, findsWidgets, reason: 'Nav rail\'da yangi birlashtirilgan bo\'lim ko\'rinishi kerak');
        await tester.tap(navBandi.first);
        await _kut(tester, marta: 6);

        // --- 1) Asosiy ro'yxatda IKKALA tur ham "Turi" ustuni bilan ---
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.text('Kamera'), findsOneWidget, reason: 'Kamera turi chipi ko\'rinishi kerak');
        expect(find.text('To\'g\'irlash'), findsOneWidget, reason: 'Kip-to\'g\'irlash turi chipi ko\'rinishi kerak');
        expect(find.textContaining('Tola #501, 105.3 kg'), findsOneWidget);
        expect(find.textContaining('Kip №7: Tola #501 -> Lint #502'), findsOneWidget);
        expect(find.text('Xato tanlandi'), findsOneWidget, reason: 'Kip-to\'g\'irlash sababi ko\'rinishi kerak');

        // --- 2) Kalendarda "bugun"ni bosamiz ---
        final bugunKatakchasi = find.descendant(
          of: find.byType(KalendarVidjeti),
          matching: find.text('${_bugun.day}'),
        );
        expect(bugunKatakchasi, findsOneWidget);
        await tester.tap(bugunKatakchasi);
        await _kut(tester, marta: 6);

        // Kun-tafsilot panelida ikkala tur ham (tasdiqlangan + rad etilgan).
        expect(find.textContaining('Lint #900, 88.0 kg'), findsOneWidget);
        expect(find.textContaining('Kip №9: Tola #700 -> Lint #701'), findsOneWidget);
        expect(
          find.textContaining('Operator xato tanlagan'),
          findsOneWidget,
          reason: 'Sabab tafsilot panelida ko\'rinishi kerak',
        );
        expect(
          find.textContaining('Kip allaqachon hisobga olingan'),
          findsOneWidget,
          reason: 'Izoh tafsilot panelida ko\'rinishi kerak',
        );
        expect(find.text('Tasdiqlangan'), findsWidgets, reason: 'Tasdiqlangan holat-chipi ko\'rinishi kerak');
        expect(find.text('Rad etilgan'), findsWidgets, reason: 'Rad etilgan holat-chipi ko\'rinishi kerak');
        expect(find.textContaining('Sinov Admin'), findsWidgets, reason: 'Kim hal qilganini bildiruvchi ism ko\'rinishi kerak');

        await server.close(force: true);
      });
    },
  );
}
