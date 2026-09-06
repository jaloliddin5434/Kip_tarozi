// partiyalar_screen.dart'dagi "sotish" (savdo) oqimida xato ko'rsatish
// muammosini sinaydi: server kutilmagan/tushunarsiz javob qaytarganda
// (ApiException BO'LMAGAN xato — masalan 200 status bilan buzilgan JSON,
// bu haqiqiy hayotda server/tarmoq nosozligida yuz berishi mumkin) admin
// hech qanday xabar olmasdan qolmasligi kerak.
//
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali
// nazorat qilinadigan (va qasddan "buzilgan") javoblar beriladi.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/screens/admin/partiyalar_screen.dart';
import 'package:kip_tarozi/state/app_state.dart';

Map<String, dynamic> _partiyaJson({String holati = 'yopiq'}) => {
  'id': 1,
  'mahsulot_id': 1,
  'mahsulot_kodi': 'tola',
  'mahsulot_nomi': 'Tola',
  'partiya_raqami': 5,
  'holati': holati,
  'yaratilgan_vaqt': '2026-09-01T00:00:00Z',
  'yopilgan_vaqt': '2026-09-02T00:00:00Z',
  'kip_soni': 10,
  'jami_kg': 500.0,
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

/// Mahalliy soxta server. `sotishJavobi` chaqiruvchi tomonidan sozlanadi —
/// shu orqali POST /sotish so'roviga turlicha (muvaffaqiyatli/buzilgan/500)
/// javob simulyatsiya qilinadi.
class _SoxtaServer {
  late HttpServer _server;
  void Function(HttpRequest req)? sotishJavobi;
  String partiyaHolati = 'yopiq';

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final yol = req.uri.path;
      if (req.method == 'GET' && yol == '/api/v1/partiyalar') {
        _javobYubor(req, 200, {
          'items': [_partiyaJson(holati: partiyaHolati)],
          'jami': 1,
          'sahifa': 1,
          'sahifa_hajmi': 100,
        });
      } else if (req.method == 'POST' && yol == '/api/v1/partiyalar/1/sotish') {
        // Tana o'qib tashlanishi kerak — aks holda ulanish osilib qolishi mumkin.
        await req.drain();
        (sotishJavobi ?? (r) => _javobYuborStatik(r, 200, _partiyaJson(holati: 'sotilgan')))(req);
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
    return _server.port;
  }

  void _javobYubor(HttpRequest req, int status, Object tana) => _javobYuborStatik(req, status, tana);

  Future<void> yopish() => _server.close(force: true);
}

void _javobYuborStatik(HttpRequest req, int status, Object tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

void _buzilganJavobYubor(HttpRequest req) {
  // 200 status, lekin tana JSON EMAS — masalan proksi/server nosozligida
  // javob o'rtadan uzilib qolgani kabi real holatni simulyatsiya qiladi.
  req.response.statusCode = 200;
  req.response.headers.contentType = ContentType.json;
  req.response.write('{buzilgan-javob-bu-json-emas');
  req.response.close();
}

void _serverXatosiYubor(HttpRequest req) {
  req.response.statusCode = 500;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode({'detail': 'Kutilmagan server xatosi'}));
  req.response.close();
}

Widget _ekranQurish(AppState holat) {
  return ChangeNotifierProvider<AppState>.value(
    value: holat,
    child: const MaterialApp(home: Scaffold(body: PartiyalarEkrani())),
  );
}

AppState _sinovHolati() {
  return AppState()
    ..api.token = 'sinov-tokeni'
    ..foydalanuvchi = Foydalanuvchi(id: 1, ism: 'Sinov Admin', login: 'admin', rol: 'admin');
}

// SnackBar'ning haqiqiy (real-time) avtomatik yopilish taymeri
// pumpAndSettle() bilan runAsync() ichida ziddiyatga kirib "timed out"
// berishi mumkin — shuning uchun aniq sonli pump()lar bilan kutamiz
// (admin_tab_almashish_test.dart'da ishlatilgan usul bilan bir xil).
Future<void> _kut(WidgetTester tester, {int marta = 6}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _sotishDialoginiOchibToldirish(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Sotildi deb belgilash'));
  await _kut(tester, marta: 10);
}

Future<void> _sotishniTasdiqlash(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Sotildi deb belgilash').last);
  await _kut(tester);
}

void main() {
  // Server HAR DOIM runAsync() ICHIDA yaratiladi — tashqarida (setUp'da)
  // yaratilsa, u boshqa "zone"da qoladi va tester.runAsync() ichidan
  // yuborilgan so'rovlar bilan to'g'ri sinxronlanmay, testni beqaror
  // qilib qo'yishi aniqlandi (button hech qachon topilmasdi).

  testWidgets(
    'Sotish: server tushunarsiz (ApiException BO\'LMAGAN) xato qaytarsa ham, foydalanuvchiga xabar ko\'rsatilishi kerak',
    (tester) async {
      final xatolar = <FlutterErrorDetails>[];
      final eskiOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        xatolar.add(details);
        eskiOnError?.call(details);
      };

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        final server = _SoxtaServer();
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';
        server.sotishJavobi = _buzilganJavobYubor;

        await tester.pumpWidget(_ekranQurish(_sinovHolati()));
        await _kut(tester, marta: 10);

        await _sotishDialoginiOchibToldirish(tester);
        await _sotishniTasdiqlash(tester);
        await _kut(tester);

        await server.yopish();
      });

      FlutterError.onError = eskiOnError;

      expect(
        xatolar,
        isEmpty,
        reason: 'Buzilgan server javobi Flutter darajasida "ushlanmagan xato"ga aylanmasligi kerak: $xatolar',
      );
      expect(
        find.byType(SnackBar),
        findsOneWidget,
        reason: 'Admin sotish muvaffaqiyatsiz bo\'lganini albatta ko\'rishi kerak (xato SnackBar)',
      );
    },
  );

  testWidgets('Sotish: server 500 qaytarsa, foydalanuvchiga xato ko\'rsatilishi kerak', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final server = _SoxtaServer();
      final port = await server.ishgaTushirish();
      ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';
      server.sotishJavobi = _serverXatosiYubor;

      await tester.pumpWidget(_ekranQurish(_sinovHolati()));
      await _kut(tester, marta: 10);

      await _sotishDialoginiOchibToldirish(tester);
      await _sotishniTasdiqlash(tester);
      await _kut(tester);

      await server.yopish();
    });

    expect(find.byType(SnackBar), findsOneWidget, reason: '500 xatosi ham SnackBar orqali ko\'rsatilishi kerak');
    expect(find.textContaining('Kutilmagan server xatosi'), findsOneWidget);
  });

  testWidgets('Sotish: muvaffaqiyatli bo\'lsa — tasdiq xabari ko\'rinishi va ro\'yxat yangilanishi kerak', (
    tester,
  ) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final server = _SoxtaServer();
      final port = await server.ishgaTushirish();
      ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';
      server.sotishJavobi = (req) {
        server.partiyaHolati = 'sotilgan';
        _javobYuborStatik(req, 200, _partiyaJson(holati: 'sotilgan'));
      };

      await tester.pumpWidget(_ekranQurish(_sinovHolati()));
      await _kut(tester, marta: 10);

      await _sotishDialoginiOchibToldirish(tester);
      await _sotishniTasdiqlash(tester);
      await _kut(tester);

      await server.yopish();
    });

    expect(find.byType(AlertDialog), findsNothing, reason: 'Muvaffaqiyatli sotishdan keyin dialog yopilishi kerak');
    expect(find.byType(SnackBar), findsOneWidget, reason: 'Muvaffaqiyatli sotish haqida ham aniq xabar berilishi kerak');
    // "Sotildi" matni ikki joyda bor: tepadagi filtr chipi (doim mavjud) va
    // endi yangilangan kartaning holat belgisi.
    expect(
      find.text('Sotildi'),
      findsNWidgets(2),
      reason: 'Ro\'yxat yangilanib, karta "Sotildi" holatini ko\'rsatishi kerak',
    );
  });
}
