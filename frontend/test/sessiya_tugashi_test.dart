// AUDIT TUZATISHI: markazlashgan "401 = avtomatik logout" mexanizmini
// sinaydi (ApiClient.bir401SodirBoldi -> AppState._sessiyaMajburiyTugadi).
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali
// (operator_partiya_race_test.dart / operator_muammoli_banner_test.dart
// naqshi bilan bir xil), shuning uchun oddiy `flutter test` bilan (backend
// kerak emas) tez va ishonchli ishlaydi.
//
// Uchta stsenariy:
//  1. ODDIY 401: operator "Saqlash" bossa, token allaqachon bekor qilingan
//     bo'lsa — avtomatik login ekraniga qaytarilishi kerak.
//  2. ENG MUHIM: "Kamera tasdiqlanmoqda" bloklovchi dialogi (PopScope
//     canPop:false — ATAYLAB chiqish yo'lisiz) ochiq turganda token bekor
//     qilinsa — keyingi poll (3s) dialogni AVTOMATIK yopib, login ekraniga
//     qaytarishi kerak.
//  3. REGRESSIYA HIMOYASI: moliyaviy bo'lim 401'lari (qo'shimcha parol
//     noto'g'ri / moliyaviy sessiya tugashi) GLOBAL logoutni ISHGA
//     TUSHIRMASLIGI kerak — bular alohida, mahalliy ma'noga ega.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/api/api_exception.dart';
import 'package:kip_tarozi/main.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/state/app_state.dart';

void _javobYubor(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

/// `sessiyaBekorQilindi`: `true` bo'lsa, sessiyaga bog'liq barcha
/// endpointlar 401 qaytaradi (real hayotda admin "Tokenlarni bekor
/// qilish"ni bosgandan keyingi holatni simulyatsiya qiladi).
/// `kameraIshlamaydi`: `true` bo'lsa, `POST /kiplar` 202
/// (kamera_tasdiq_kutilmoqda) qaytaradi — operator ekranini bloklovchi
/// dialogni chiqarish uchun.
class _SoxtaServer {
  late HttpServer _server;
  bool sessiyaBekorQilindi = false;
  bool kameraIshlamaydi = false;
  int kameraPollSoni = 0;

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final yol = req.uri.path;
      if (yol == '/api/v1/kamera-tasdiq/1/holat') kameraPollSoni++;

      // MUHIM: faqat aniq shu 3 ta yo'l — ayniqsa
      // `/kamera-tasdiq/mening-kutilayotganim` (boshqa, 5s'lik
      // `_blokniTekshirish()` fon so'rovi) ATAYLAB BUNGA KIRITILMAGAN, aks
      // holda 2-stsenariy o'sha (bu testda tekshirilayotgan `_kameraTasdiqPoll`
      // EMAS) yo'l orqali tasodifan 401 olib, testni noaniq qilib qo'yardi.
      if (sessiyaBekorQilindi &&
          (yol == '/api/v1/auth/men' || yol == '/api/v1/kiplar' || yol == '/api/v1/kamera-tasdiq/1/holat')) {
        _javobYubor(req, 401, {'detail': "Token yaroqsiz yoki muddati o'tgan"});
        return;
      }

      if (req.method == 'POST' && yol == '/api/v1/auth/login') {
        _javobYubor(req, 200, {'access_token': 'sinov-tokeni'});
      } else if (req.method == 'GET' && yol == '/api/v1/auth/men') {
        _javobYubor(req, 200, {'id': 1, 'ism': 'Sinov Operator', 'login': 'operator_a', 'rol': 'operator', 'smena': 'A'});
      } else if (req.method == 'GET' && yol == '/api/v1/mahsulotlar') {
        _javobYubor(req, 200, [
          {'id': 1, 'kod': 'tola', 'nomi': 'Tola'},
        ]);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/smena/holati') {
        _javobYubor(req, 200, {'smena': 'A', 'sana': '2026-09-01', 'mahsulotlar': []});
      } else if (req.method == 'GET' && yol == '/api/v1/shubhali-holatlar/bloklovchi') {
        _javobYubor(req, 200, null);
      } else if (req.method == 'GET' && yol == '/api/v1/kamera-tasdiq/mening-kutilayotganim') {
        _javobYubor(req, 200, null);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/kamera-sozlamalari') {
        _javobYubor(req, 200, {'agent_surat_url': null});
      } else if (req.method == 'GET' && yol == '/api/v1/partiyalar/ochiq') {
        _javobYubor(req, 200, []);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/smena/royxat') {
        _javobYubor(req, 200, []);
      } else if (req.method == 'POST' && yol == '/api/v1/partiyalar') {
        _javobYubor(req, 200, {
          'id': 1,
          'mahsulot_id': 1,
          'mahsulot_kodi': 'tola',
          'mahsulot_nomi': 'Tola',
          'partiya_raqami': 9001,
          'holati': 'ochiq',
          'yaratilgan_vaqt': '2026-09-01T00:00:00Z',
          'yopilgan_vaqt': null,
          'kip_soni': 0,
          'jami_kg': 0.0,
          'sotuv_sanasi': null,
          'xaridor': null,
          'dogovor_raqami': null,
          'nakladnoy_raqami': null,
          'sort': null,
          'urama_bilan_vazn': null,
          'urama_vazni': null,
          'sof_vazn': null,
          'kondicion_vazni': null,
        });
      } else if (req.method == 'POST' && yol == '/api/v1/kiplar') {
        if (kameraIshlamaydi) {
          _javobYubor(req, 202, {'kamera_tasdiq_kutilmoqda': true, 'sorov_id': 1, 'holati': 'kutilmoqda'});
        } else {
          _javobYubor(req, 201, {
            'id': 1,
            'kip_raqami': 1,
            'partiya_id': 1,
            'ogirlik': 100.0,
            'surat_yoli': null,
            'vaqt': '2026-09-01T00:00:00Z',
          });
        }
      } else if (req.method == 'GET' && yol == '/api/v1/kamera-tasdiq/1/holat') {
        // 401 tekshiruvi yuqorida (sessiyaBekorQilindi) allaqachon amalga
        // oshdi — bu yergacha yetib kelgan bo'lsa, hali "kutilmoqda".
        _javobYubor(req, 200, {'id': 1, 'holati': 'kutilmoqda', 'kip_id': null, 'izoh': null});
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  Future<void> yopish() => _server.close(force: true);
}

/// `pump()` real IO bilan sinxronlanmagani uchun, real vaqt kechikishi bilan
/// birga bir necha marta pump qilamiz (loyihadagi boshqa real-IO testlar
/// bilan bir xil naqsh).
Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 200)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

/// Login ekranidan "Operator" -> smena "A" -> parol -> "Kirish" orqali
/// operator ekraniga o'tadi (login_screen.dart real oqimi).
Future<void> _operatorSifatidaKirish(WidgetTester tester) async {
  await tester.tap(find.text('Operator'));
  await tester.pump();
  await tester.tap(find.text('A').first);
  await tester.pump();
  await tester.enterText(find.byType(TextField).first, 'istalgan-parol');
  await tester.pump();
  await tester.tap(find.text('Kirish'));
  await _kut(tester, marta: 6);
}

void main() {
  testWidgets(
    '1-STSENARIY (oddiy 401): token bekor qilingandan keyin "Saqlash" bossa, avtomatik login ekraniga qaytariladi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late _SoxtaServer server;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = _SoxtaServer();
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        await tester.pumpWidget(const KipTaroziApp());
        await _kut(tester, marta: 3);

        await _operatorSifatidaKirish(tester);
        expect(find.text('Tola'), findsWidgets, reason: 'Login muvaffaqiyatli bo\'lib, operator ekraniga o\'tishi kerak');

        // --- Admin operatorning tokenini bekor qildi (real hayotda —
        // Sozlamalar ekranidan) ---
        server.sessiyaBekorQilindi = true;

        // Partiya tanlab, og'irlik kiritib "Saqlash" bosamiz. ("Tola" ikki
        // marta ko'rinadi — chap paneldagi mahsulot tugmasi VA o'rtadagi
        // "bugungi ko'rsatkich" kartasi; `.first` chap paneldagi tugma.)
        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 3);
        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '9001');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 3);
        await tester.enterText(find.byType(TextField).last, '100');
        await tester.pump();

        final saqlashTugmasi = find.text('Saqlash');
        _agarTopilmasaMatnlarniChiqar(saqlashTugmasi, 'Saqlash tugmasi bosishdan oldin');
        await tester.tap(saqlashTugmasi);
        await _kut(tester, marta: 6);

        await server.yopish();
      });

      // Login ekraniga avtomatik qaytarilgan bo'lishi kerak — rol tanlash
      // tugmalari (faqat login ekranida bo'ladi) qayta ko'rinadi.
      _agarTopilmasaMatnlarniChiqar(find.text('Operator'), 'yakunda (401dan keyin)');
      expect(find.text('Operator'), findsOneWidget, reason: 'Login ekraniga (rol tanlash bosqichiga) qaytarilishi kerak');
      expect(find.text('Tola'), findsNothing, reason: 'Operator ekrani endi ko\'rinmasligi kerak');
      expect(
        find.textContaining('qaytadan kiring'),
        findsOneWidget,
        reason: '"Sessiyangiz tugadi — qaytadan kiring" xabari ko\'rsatilishi kerak',
      );
    },
  );

  testWidgets(
    '2-STSENARIY (ENG MUHIM): "Kamera tasdiqlanmoqda" bloklovchi dialogi ochiq bo\'lsa, token bekor qilinishi dialogni yopib login ekraniga qaytaradi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late _SoxtaServer server;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = _SoxtaServer()..kameraIshlamaydi = true;
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        await tester.pumpWidget(const KipTaroziApp());
        await _kut(tester, marta: 3);

        await _operatorSifatidaKirish(tester);
        expect(find.text('Tola'), findsWidgets);

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 3);
        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '9001');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 3);
        await tester.enterText(find.byType(TextField).last, '100');
        await tester.pump();
        _agarTopilmasaMatnlarniChiqar(find.text('Saqlash'), 'Saqlash tugmasi bosishdan oldin (2-stsenariy)');
        await tester.tap(find.text('Saqlash'));
        await _kut(tester, marta: 3);

        // Kamera ishlamagani uchun "Kamera tasdiqlanmoqda" BLOKLOVCHI dialogi
        // ochilgan bo'lishi kerak (PopScope canPop:false — chiqish yo'lisiz).
        expect(find.byType(AlertDialog), findsOneWidget, reason: 'Kamera-tasdiq kutish dialogi ochilishi kerak');

        // --- Aynan shu daqiqada admin operatorning tokenini bekor qildi ---
        server.sessiyaBekorQilindi = true;
        final pollDanOldin = server.kameraPollSoni;

        // Poll har 3 soniyada (_kameraTasdiqPoll) — dialog yopilishini
        // kutamiz (SnackBar 6s'dan keyin o'zi yo'qoladi, shuning uchun
        // aniq shu paytda — kechiktirmasdan — tekshiramiz).
        for (var i = 0; i < 12; i++) {
          await Future.delayed(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          if (find.byType(AlertDialog).evaluate().isEmpty) break;
        }

        expect(
          server.kameraPollSoni,
          greaterThan(pollDanOldin),
          reason: 'Poll haqiqatan ham qayta so\'ralgan (va 401 olgan) bo\'lishi kerak',
        );
        expect(find.byType(AlertDialog), findsNothing, reason: 'Bloklovchi dialog AVTOMATIK yopilishi kerak');
        expect(find.text('Operator'), findsOneWidget, reason: 'Login ekraniga qaytarilishi kerak');
        expect(
          find.textContaining('qaytadan kiring'),
          findsOneWidget,
          reason: '"Sessiyangiz tugadi — qaytadan kiring" xabari ko\'rsatilishi kerak',
        );

        await server.yopish();
      });
    },
  );

  testWidgets(
    '3-STSENARIY (regressiya himoyasi): moliyaviy 401 (parol noto\'g\'ri) global logoutni ISHGA TUSHIRMAYDI',
    (tester) async {
      late HttpServer moliyaviyServer;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        moliyaviyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        moliyaviyServer.listen((req) async {
          if (req.method == 'POST' && req.uri.path == '/api/v1/moliyaviy/kirish') {
            _javobYubor(req, 401, {'detail': "Moliyaviy parol noto'g'ri"});
          } else {
            req.response.statusCode = 404;
            await req.response.close();
          }
        });
        ApiClient.bazaUrl = 'http://127.0.0.1:${moliyaviyServer.port}/api/v1';

        final holat = AppState()
          ..api.token = 'asosiy-admin-tokeni'
          ..foydalanuvchi = Foydalanuvchi(id: 1, ism: 'Sinov Admin', login: 'admin', rol: 'admin');

        expect(holat.kirilgan, isTrue);

        ApiException? tutilganXato;
        try {
          await holat.moliyaviyKirish('notogri-parol');
        } on ApiException catch (e) {
          tutilganXato = e;
        }

        expect(tutilganXato, isNotNull, reason: '401 ApiException sifatida chaqiruvchiga yetib borishi kerak (ekran o\'zi ko\'rsatadi)');
        expect(tutilganXato!.statusCode, 401);
        expect(holat.kirilgan, isTrue, reason: 'Moliyaviy parol xatosi ASOSIY sessiyani yopmasligi kerak');
        expect(holat.foydalanuvchi, isNotNull, reason: 'Global logout ishga tushmagan bo\'lishi kerak');
        expect(holat.api.token, 'asosiy-admin-tokeni', reason: 'Asosiy token o\'zgarishsiz qolishi kerak');

        await moliyaviyServer.close(force: true);
      });
    },
  );
}

void _agarTopilmasaMatnlarniChiqar(Finder finder, String bosqich) {
  if (finder.evaluate().isEmpty) {
    final matnlar = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList();
    // ignore: avoid_print
    print('DEBUG [$bosqich] joriy matnlar: $matnlar');
  }
}
