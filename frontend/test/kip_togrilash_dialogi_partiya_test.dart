// AUDIT TUZATISHI (UX): kip_togrilash_dialogi.dart'dagi "Partiya raqami"
// maydoni endi (operator ekranidagi mavjud naqsh bilan bir xil) tanlangan
// mahsulot uchun HOZIRGI OCHIQ partiyalar ro'yxatini chip ko'rinishida
// ko'rsatadi, mahsulot almashtirilsa ro'yxat yangilanadi, VA baribir erkin
// (faqat-raqam) qo'lda kiritishga ham ruxsat beradi.
//
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/mahsulot.dart';
import 'package:kip_tarozi/state/app_state.dart';
import 'package:kip_tarozi/widgets/kip_togrilash_dialogi.dart';

void _javobYubor(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

Map<String, dynamic> _partiyaJson({required int raqam, required int kipSoni}) => {
      'id': raqam,
      'mahsulot_id': 1,
      'mahsulot_kodi': 'tola',
      'mahsulot_nomi': 'Tola',
      'partiya_raqami': raqam,
      'holati': 'ochiq',
      'yaratilgan_vaqt': '2026-09-01T00:00:00Z',
      'yopilgan_vaqt': null,
      'kip_soni': kipSoni,
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
    };

class _SoxtaServer {
  late HttpServer _server;
  Map<String, dynamic>? songgiKipTogrilashSorovi;

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final yol = req.uri.path;
      final mahsulotKodi = req.uri.queryParameters['mahsulot_kodi'];

      if (req.method == 'GET' && yol == '/api/v1/partiyalar/ochiq' && mahsulotKodi == 'tola') {
        _javobYubor(req, 200, [
          _partiyaJson(raqam: 501, kipSoni: 3),
          _partiyaJson(raqam: 502, kipSoni: 1),
        ]);
      } else if (req.method == 'GET' && yol == '/api/v1/partiyalar/ochiq' && mahsulotKodi == 'lint') {
        _javobYubor(req, 200, [
          _partiyaJson(raqam: 700, kipSoni: 0),
        ]);
      } else if (req.method == 'POST' && yol == '/api/v1/kip-togrilash') {
        songgiKipTogrilashSorovi = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        _javobYubor(req, 201, {'id': 1, 'holati': 'kutilmoqda', 'izoh': null});
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  Future<void> yopish() => _server.close(force: true);
}

Future<void> _kut(WidgetTester tester, {int marta = 6, Duration bosqich = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(bosqich);
    await tester.pump(bosqich);
  }
}

Widget _hostQurish(AppState holat, List<Mahsulot> mahsulotlar) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => kipTogrilashDialogniKorsat(
            context: context,
            holat: holat,
            mahsulotlar: mahsulotlar,
            kipId: 42,
            kipRaqami: 7,
            ogirlik: 135.5,
          ),
          child: const Text('dialogni och'),
        ),
      ),
    ),
  );
}

void main() {
  final mahsulotlar = [
    Mahsulot(id: 1, kod: 'tola', nomi: 'Tola'),
    Mahsulot(id: 2, kod: 'lint', nomi: 'Lint'),
  ];

  testWidgets(
    'Kip to\'g\'rilash dialogi: mahsulot tanlanganda ochiq partiyalar chip qilib ko\'rsatiladi va bosilsa maydonga yoziladi',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      late _SoxtaServer server;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = _SoxtaServer();
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        final holat = AppState()..api.token = 'sinov-tokeni';
        await tester.pumpWidget(_hostQurish(holat, mahsulotlar));

        await tester.tap(find.text('dialogni och'));
        await tester.pumpAndSettle();

        // Hali mahsulot tanlanmagan — ochiq partiyalar bo'limi yo'q.
        expect(find.text('Ochiq partiyalar'), findsNothing);

        await tester.tap(find.text('Tola'));
        await _kut(tester);

        expect(find.text('Ochiq partiyalar'), findsOneWidget, reason: 'Mahsulot tanlangach ochiq partiyalar sarlavhasi ko\'rinishi kerak');
        expect(find.text('#501 (3)'), findsOneWidget);
        expect(find.text('#502 (1)'), findsOneWidget);

        // Chip bosiladi — partiya raqami maydoniga yoziladi.
        await tester.tap(find.text('#501 (3)'));
        await tester.pump();
        final partiyaMaydoni = tester.widget<TextField>(find.byType(TextField).first);
        expect(partiyaMaydoni.controller!.text, '501');

        // --- Mahsulot ALMASHTIRILADI — ro'yxat yangi mahsulotga mos yangilanishi kerak ---
        await tester.tap(find.text('Lint'));
        await _kut(tester);

        expect(find.text('#501 (3)'), findsNothing, reason: 'Eski mahsulotning partiyalari endi ko\'rinmasligi kerak');
        expect(find.text('#502 (1)'), findsNothing);
        expect(find.text('#700 (0)'), findsOneWidget, reason: 'Yangi mahsulotning ochiq partiyasi ko\'rinishi kerak');
        final maydonMahsulotAlmashgach = tester.widget<TextField>(find.byType(TextField).first);
        expect(maydonMahsulotAlmashgach.controller!.text, '', reason: 'Mahsulot almashtirilganda eski partiya raqami tozalanishi kerak');

        // --- Ro'yxatda YO'Q raqamni ham qo'lda (FAQAT RAQAM) kiritish mumkin ---
        await tester.enterText(find.byType(TextField).first, '9a9b9');
        await tester.pump();
        final qolDaKiritilgan = tester.widget<TextField>(find.byType(TextField).first);
        expect(qolDaKiritilgan.controller!.text, '999', reason: 'Harflar filtrlanib, faqat raqamlar qolishi kerak');

        // --- To'liq yuborish oqimi ---
        await tester.enterText(find.byType(TextField).last, 'operator noto\'g\'ri mahsulot tanlagan');
        await tester.pump();
        await tester.tap(find.text('Zayavka yuborish'));
        await _kut(tester);

        expect(server.songgiKipTogrilashSorovi, isNotNull);
        expect(server.songgiKipTogrilashSorovi!['yangi_mahsulot_kodi'], 'lint');
        expect(server.songgiKipTogrilashSorovi!['yangi_partiya_raqami'], 999);

        await server.yopish();
      });
    },
  );
}
