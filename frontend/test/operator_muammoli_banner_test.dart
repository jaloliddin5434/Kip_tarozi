// 5-QISM (audit topilmasi): "muammoli" (dead-letter) offline yozuvlar bo'lsa,
// operator ekranida ko'rinadigan (qizil) ogohlantirish banneri chiqishini
// tasdiqlaydi. Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer
// orqali (operator_partiya_race_test.dart naqshi bilan bir xil).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/screens/operator/operator_screen.dart';
import 'package:kip_tarozi/state/app_state.dart';

void _javobYubor(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

class _SoxtaServer {
  late HttpServer _server;

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
      } else if (req.method == 'GET' && yol == '/api/v1/partiyalar/ochiq') {
        _javobYubor(req, 200, []);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/smena/royxat') {
        _javobYubor(req, 200, []);
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  Future<void> yopish() => _server.close(force: true);
}

Widget _ekranQurish(AppState holat) {
  return ChangeNotifierProvider<AppState>.value(value: holat, child: const MaterialApp(home: OperatorEkrani()));
}

AppState _sinovHolati() {
  return AppState()
    ..api.token = 'sinov-tokeni'
    ..foydalanuvchi = Foydalanuvchi(id: 1, ism: 'Sinov Operator', login: 'operator_a', rol: 'operator', smena: 'A');
}

void main() {
  testWidgets(
    'Operator ekrani: muammoli (dead-letter) offline yozuv bo\'lsa qizil ogohlantirish banneri ko\'rinadi',
    (tester) async {
      // OfflineKipNavbati.royxat() shu SharedPreferences kalitidan o'qiydi —
      // oldindan bitta "muammoli: true" yozuv bilan to'ldiramiz (xuddi
      // sinxronla() backend tomonidan qat'iy rad etilgandan keyin qoldiradigan
      // holat bilan bir xil shaklda).
      SharedPreferences.setMockInitialValues({
        'offline_kip_navbati_v1': jsonEncode([
          {
            'tana': {
              'mijoz_id': 'muammoli-1',
              'partiya_id': 1,
              'ogirlik': 100.0,
              'mahalliy_vaqt': '2026-09-01T00:00:00Z',
            },
            'token': 'eski-token',
            'qoshilgan': '2026-09-01T00:00:00Z',
            'muammoli': true,
            'muammoliXabari': 'Partiya topilmadi',
          },
        ]),
      });

      // Standart test-oyna (800px) AppBar'dagi barcha indikatorlarga
      // sig'maydi (real ish stolida muammo emas) — kengroq oyna beramiz.
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

        await tester.pumpWidget(_ekranQurish(_sinovHolati()));
        // initState() ichidagi _navbatUzunliginiYangilash() (async, SharedPreferences
        // o'qiydi) va boshqa yuklashlar tugashi uchun bir necha marta pump qilamiz.
        for (var i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }

        await server.yopish();
      });

      expect(
        find.textContaining('sinxronlanmadi'),
        findsOneWidget,
        reason: 'Muammoli yozuv borligi haqida qizil banner ko\'rinishi kerak',
      );
    },
  );

  testWidgets(
    'Operator ekrani: muammoli yozuv YO\'Q bo\'lsa banner ko\'rinmaydi',
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

        await tester.pumpWidget(_ekranQurish(_sinovHolati()));
        for (var i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }

        await server.yopish();
      });

      expect(find.textContaining('sinxronlanmadi'), findsNothing);
    },
  );
}
