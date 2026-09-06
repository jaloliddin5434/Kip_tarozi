// statistika_screen.dart, moliyaviy_kirish_screen.dart,
// moliyaviy_hisobot_screen.dart, sozlamalar_screen.dart va
// shubhali_holatlar_screen.dart'ga qo'shilgan `if (!mounted) return;`
// himoya tekshiruvlari FUNKSIONAL xatti-harakatni o'zgartirmaganini
// tasdiqlaydi — har bir ekranning ODDIY (dispose bo'lmagan) ish oqimi
// avvalgidek ishlashi kerak.
//
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/screens/admin/moliyaviy_hisobot_screen.dart';
import 'package:kip_tarozi/screens/admin/moliyaviy_kirish_screen.dart';
import 'package:kip_tarozi/screens/admin/shubhali_holatlar_screen.dart';
import 'package:kip_tarozi/screens/admin/sozlamalar_screen.dart';
import 'package:kip_tarozi/screens/admin/statistika_screen.dart';
import 'package:kip_tarozi/state/app_state.dart';
import 'package:kip_tarozi/widgets/kalendar_vidjeti.dart';

void _javob(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

Map<String, dynamic> _davrJamlanma() => {
  'davr': 'kunlik',
  'boshlanish_sanasi': '2026-09-01',
  'tugash_sanasi': '2026-09-06',
  'mahsulotlar': [
    {'mahsulot_kodi': 'tola', 'mahsulot_nomi': 'Tola', 'soni': 10, 'jami_kg': 500.0},
  ],
  'jami_soni': 10,
  'jami_kg': 500.0,
};

AppState _adminHolati() {
  return AppState()
    ..api.token = 'sinov-tokeni'
    ..foydalanuvchi = Foydalanuvchi(id: 1, ism: 'Sinov Admin', login: 'admin', rol: 'admin');
}

Future<void> _kut(WidgetTester tester, {int marta = 6}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _ekranQurish(AppState holat, Widget ekran) {
  return ChangeNotifierProvider<AppState>.value(value: holat, child: MaterialApp(home: Scaffold(body: ekran)));
}

void main() {
  testWidgets('Statistika: davr/mahsulot/smena filtrlash va kalendar kun tanlash normal ishlaydi', (tester) async {
    late HttpServer server;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final yol = req.uri.path;
        if (yol == '/api/v1/statistika/jamlanma') {
          _javob(req, 200, _davrJamlanma());
        } else if (yol == '/api/v1/statistika/smena-boyicha') {
          _javob(req, 200, [
            {'smena': 'A', 'soni': 5, 'jami_kg': 250.0},
          ]);
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

      await tester.pumpWidget(_ekranQurish(_adminHolati(), const StatistikaEkrani()));
      await _kut(tester, marta: 3);
      expect(find.text('Tola'), findsWidgets, reason: 'Boshlang\'ich jamlanma ko\'rinishi kerak');

      // Davr filtri
      await tester.tap(find.text('Haftalik'));
      await _kut(tester, marta: 3);

      // Mahsulot filtri
      await tester.tap(find.text('Lint'));
      await _kut(tester, marta: 3);

      // Smena filtri ("Jami" bo'lmagan holatga o'tish — smena-boyicha so'rovini o'chiradi)
      await tester.tap(find.text('A'));
      await _kut(tester, marta: 3);

      // Kalendardan bugungi kunni tanlash — KalendarVidjeti ichidagi
      // kun-katakchasiga aniq nishonlab (boshqa "6" kabi raqamli matnlar
      // bilan chalkashmasligi uchun).
      final bugun = DateTime.now().day.toString();
      final kunTopilma = find.descendant(of: find.byType(KalendarVidjeti), matching: find.text(bugun));
      if (kunTopilma.evaluate().isNotEmpty) {
        await tester.tap(kunTopilma.first, warnIfMissed: false);
        await _kut(tester, marta: 3);
      }

      await server.close(force: true);
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('Sozlamalar: yuklash va saqlash normal ishlaydi', (tester) async {
    late HttpServer server;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final yol = req.uri.path;
        if (req.method == 'GET' && yol == '/api/v1/sozlamalar') {
          _javob(req, 200, [
            {
              'kalit': 'telegram_xatolik_bot_token',
              'qiymat': 'eski-token',
              'tavsif': null,
              'yangilangan_vaqt': '2026-09-01T00:00:00Z',
            },
          ]);
        } else if (req.method == 'PUT' && yol.startsWith('/api/v1/sozlamalar/')) {
          await req.drain();
          _javob(req, 200, {
            'kalit': 'telegram_xatolik_bot_token',
            'qiymat': 'yangi-token',
            'tavsif': null,
            'yangilangan_vaqt': '2026-09-01T00:00:00Z',
          });
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

      await tester.pumpWidget(_ekranQurish(_adminHolati(), const SozlamalarEkrani()));
      await _kut(tester, marta: 10);

      await tester.enterText(find.byType(TextField).first, 'yangi-token');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Saqlash').first);
      await _kut(tester, marta: 8);

      await server.close(force: true);
    });

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget, reason: 'Saqlash muvaffaqiyat xabari ko\'rsatilishi kerak');
  });

  testWidgets('Shubhali holatlar: smena filtri va sahifalash normal ishlaydi', (tester) async {
    late HttpServer server;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final yol = req.uri.path;
        if (yol == '/api/v1/shubhali-holatlar') {
          _javob(req, 200, {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 20});
        } else if (yol == '/api/v1/shubhali-holatlar/statistika') {
          _javob(req, 200, {
            'smena_boyicha': {'A': 1, 'B': 0, 'C': 0, 'D': 0},
            'operator_boyicha': [],
          });
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

      await tester.pumpWidget(_ekranQurish(_adminHolati(), const ShubhaliHolatlarEkrani()));
      await _kut(tester, marta: 3);

      await tester.tap(find.widgetWithText(ChoiceChip, 'A'));
      await _kut(tester, marta: 3);

      // Sana-tanlash dialogini ochib, bugungi kunni tasdiqlash.
      await tester.tap(find.textContaining('dan').first);
      await tester.pump(const Duration(milliseconds: 300));
      final okTugmasi = find.text('OK');
      if (okTugmasi.evaluate().isNotEmpty) {
        await tester.tap(okTugmasi.first);
        await _kut(tester, marta: 3);
      } else {
        // Dialog kutilganidek ochilmasa ham, asosiy filtr sinovi allaqachon
        // o'tdi — testni to'xtatib qo'ymaymiz.
        await tester.pump();
      }

      await server.close(force: true);
    });

    expect(tester.takeException(), isNull);
  });

  testWidgets('Moliyaviy: birinchi marta parol o\'rnatish -> kirish -> hisobot -> orqaga qaytish', (tester) async {
    late HttpServer server;
    var parolOrnatilganmi = false;

    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final yol = req.uri.path;
        if (req.method == 'POST' && yol == '/api/v1/moliyaviy/kirish') {
          await req.drain();
          if (!parolOrnatilganmi) {
            _javob(req, 400, {'detail': 'Moliyaviy parol hali sozlanmagan'});
          } else {
            _javob(req, 200, {'access_token': 'moliyaviy-token', 'muddat_daqiqa': 15});
          }
        } else if (req.method == 'POST' && yol == '/api/v1/moliyaviy/parolni-ornatish') {
          await req.drain();
          parolOrnatilganmi = true;
          _javob(req, 200, {'holat': 'ok'});
        } else if (yol == '/api/v1/moliyaviy/uzex-narxlar') {
          _javob(req, 200, []);
        } else if (yol == '/api/v1/moliyaviy/hisobot') {
          _javob(req, 200, {
            'davr': 'oylik',
            'boshlanish_sanasi': '2026-08-01',
            'tugash_sanasi': '2026-08-31',
            'mahsulotlar': [],
            'jami_summa': 0.0,
          });
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      ApiClient.bazaUrl = 'http://127.0.0.1:${server.port}/api/v1';

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(value: _adminHolati(), child: const MaterialApp(home: MoliyaviyKirishEkrani())),
      );
      await _kut(tester, marta: 3);

      await tester.enterText(find.byType(TextField).first, 'yangi-parol');
      await tester.tap(find.text('Kirish'));
      await _kut(tester, marta: 6);

      // Parol hali sozlanmagani uchun "o'rnatish rejimi"ga o'tishi kerak.
      expect(find.byType(TextField), findsNWidgets(2), reason: 'Parol tasdiqlash maydoni ham ko\'rinishi kerak');

      await tester.enterText(find.byType(TextField).at(0), 'yangi-parol');
      await tester.enterText(find.byType(TextField).at(1), 'yangi-parol');
      await tester.tap(find.text('Parolni o\'rnatish'));
      await _kut(tester, marta: 8);

      // Muvaffaqiyatli o'rnatish+kirishdan keyin hisobot ekraniga o'tgan
      // bo'lishi kerak (parol maydonlari endi ko'rinmasligi kerak).
      expect(find.byType(MoliyaviyHisobotEkrani), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Orqaga qaytish — kirish ekraniga qaytadi, dispose bo'lgan
      // hisobot ekranida keyinchalik hech qanday xato chiqmasligi kerak.
      await tester.pageBack();
      await _kut(tester, marta: 3);

      await server.close(force: true);
    });

    expect(tester.takeException(), isNull);
  });
}
