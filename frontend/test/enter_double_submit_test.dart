// AUDIT TUZATISHI: Enter-tugma (onSubmitted) orqali "band" holatni chetlab
// o'tish mumkin bo'lgan ikkita joyni sinaydi:
//  1. operator_screen.dart — og'irlik maydonida Enter, "Saqlash"dan keyingi
//     3s sovish davrida (_saqlashVaqtinchaNofaol) qayta _saqlash()
//     chaqirilmasligi kerak (tugma xuddi shu holatda o'chirilgan bo'lardi).
//  2. login_screen.dart — parol maydonida Enter tez-tez bosilganda faqat
//     BITTA /auth/login so'rovi ketishi kerak (tugma bilan bir xil
//     `_yuklanmoqda` sharti).
//
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali
// (operator_partiya_race_test.dart naqshi bilan bir xil).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/screens/login_screen.dart';
import 'package:kip_tarozi/screens/operator/operator_screen.dart';
import 'package:kip_tarozi/state/app_state.dart';

void _javobYubor(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

Future<void> _kut(WidgetTester tester, {int marta = 10, Duration bosqich = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

// --- 1-STSENARIY: operator ekrani, "Saqlash"dan keyingi 3s sovish davri ---

class _KipSoxtaServer {
  late HttpServer _server;
  int kipPostSoni = 0;
  int _keyingiKipId = 500;

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final yol = req.uri.path;
      if (req.method == 'GET' && yol == '/api/v1/mahsulotlar') {
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
        final tana = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        _javobYubor(req, 200, {
          'id': 1,
          'mahsulot_id': 1,
          'mahsulot_kodi': 'tola',
          'mahsulot_nomi': 'Tola',
          'partiya_raqami': tana['partiya_raqami'],
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
        kipPostSoni++;
        _keyingiKipId++;
        _javobYubor(req, 201, {
          'id': _keyingiKipId,
          'kip_raqami': kipPostSoni,
          'partiya_id': 1,
          'ogirlik': 100.0,
          'surat_yoli': null,
          'vaqt': '2026-09-01T00:00:00Z',
        });
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  Future<void> yopish() => _server.close(force: true);
}

Widget _operatorEkraniQurish(AppState holat) {
  return ChangeNotifierProvider<AppState>.value(value: holat, child: const MaterialApp(home: OperatorEkrani()));
}

AppState _operatorSinovHolati() {
  return AppState()
    ..api.token = 'sinov-tokeni'
    ..foydalanuvchi = Foydalanuvchi(id: 1, ism: 'Sinov Operator', login: 'operator_a', rol: 'operator', smena: 'A');
}

// --- 2-STSENARIY: login ekrani, parol maydonida tez-tez Enter ---

class _LoginSoxtaServer {
  late HttpServer _server;
  int loginPostSoni = 0;

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      if (req.method == 'POST' && req.uri.path == '/api/v1/auth/login') {
        loginPostSoni++;
        // Real tarmoq kechikishini simulyatsiya qilamiz — shu kechikish
        // ICHIDA tez-tez Enter bosilsa, tuzatilmagan kodda BIRDAN ORTIQ
        // so'rov ketgan bo'lardi.
        await Future.delayed(const Duration(milliseconds: 300));
        _javobYubor(req, 200, {'access_token': 'sinov-tokeni'});
      } else if (req.method == 'GET' && req.uri.path == '/api/v1/auth/men') {
        _javobYubor(req, 200, {'id': 2, 'ism': 'Sinov Operator', 'login': 'operator_a', 'rol': 'operator', 'smena': 'A'});
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  Future<void> yopish() => _server.close(force: true);
}

Widget _loginEkraniQurish() {
  return ChangeNotifierProvider<AppState>(
    create: (_) => AppState(),
    child: const MaterialApp(home: LoginEkrani()),
  );
}

void main() {
  testWidgets(
    '1-STSENARIY: og\'irlik maydonida Enter — Saqlashdan keyingi 3s sovish davrida qayta chaqirilmaydi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late _KipSoxtaServer server;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = _KipSoxtaServer();
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        await tester.pumpWidget(_operatorEkraniQurish(_operatorSinovHolati()));
        await _kut(tester, marta: 5);

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 3);

        await tester.enterText(find.widgetWithText(TextField, 'Partiya raqami'), '7001');
        await tester.tap(find.text('Partiyani tanlash'));
        await _kut(tester, marta: 3);

        final ogirlikMaydoni = find.byType(TextField).last;
        await tester.enterText(ogirlikMaydoni, '100');
        await tester.pump();
        await tester.tap(find.text('Saqlash'));
        await _kut(tester, marta: 5);

        expect(find.text('Kip saqlandi'), findsOneWidget, reason: 'Birinchi saqlash muvaffaqiyatli bo\'lishi kerak');
        expect(server.kipPostSoni, 1);

        // --- Aynan shu daqiqada (3s sovish davri ichida) og'irlik
        // maydonida Enter bosiladi — maydon endi BO'SH (saqlashdan keyin
        // tozalangan). Tuzatilmagan kodda bu `_saqlash()`ni qayta chaqirib,
        // "Og'irlikni kiriting" degan CHALG'ITUVCHI xatoni ko'rsatardi.
        await tester.showKeyboard(ogirlikMaydoni);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _kut(tester, marta: 3);

        expect(
          find.textContaining('kiriting'),
          findsNothing,
          reason: 'Sovish davrida Enter bosilsa HECH QANDAY xato/qayta-chaqiruv bo\'lmasligi kerak',
        );
        expect(server.kipPostSoni, 1, reason: 'Ikkinchi POST /kiplar ketmasligi kerak');

        // Sovish davri tugagach — Enter yana ishlashi kerak (funksionallik
        // butunlay o'chirilmagan, faqat vaqtincha).
        await _kut(tester, marta: 20, bosqich: const Duration(milliseconds: 200)); // ~4s kutish
        await tester.enterText(ogirlikMaydoni, '55');
        await tester.pump();
        await tester.showKeyboard(ogirlikMaydoni);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _kut(tester, marta: 5);
        expect(server.kipPostSoni, 2, reason: 'Sovish davri tugagach Enter yana ishlashi kerak');

        await server.yopish();
      });
    },
  );

  testWidgets(
    '2-STSENARIY: parol maydonida tez-tez Enter — faqat BITTA /auth/login so\'rovi ketadi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      late _LoginSoxtaServer server;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = _LoginSoxtaServer();
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        await tester.pumpWidget(_loginEkraniQurish());
        await tester.pump();

        await tester.tap(find.text('Operator'));
        await tester.pump();
        await tester.tap(find.text('A').first);
        await tester.pump();

        final parolMaydoni = find.byType(TextField).first;
        await tester.enterText(parolMaydoni, 'sinov-paroli');
        await tester.pump();

        // Tez-tez (birinchi javob qaytishini kutmasdan) 5 marta Enter.
        await tester.showKeyboard(parolMaydoni);
        for (var i = 0; i < 5; i++) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump(const Duration(milliseconds: 20));
        }

        // Server javobi (300ms kechikish) va login-dan keyingi /auth/men
        // so'rovi tugashini kutamiz.
        await _kut(tester, marta: 10, bosqich: const Duration(milliseconds: 100));

        await server.yopish();
      });

      expect(server.loginPostSoni, 1, reason: 'Tez-tez Enter bosilsa ham FAQAT bitta /auth/login so\'rovi ketishi kerak');
    },
  );
}
