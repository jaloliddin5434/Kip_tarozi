// operator_screen.dart'dagi _partiyaniOchish() funksiyasidagi
// "stale-response race condition"ni sinaydi: operator tez-tez turli partiya
// raqamlarini kiritib "Partiyani tanlash"ni bossa, oldingi (sekinroq)
// so'rovning javobi keyingi (tezroq) javobdan KEYIN kelib, ekranda NOTO'G'RI
// partiya tanlangan bo'lib qolmasligi kerak.
//
// Haqiqiy backendga ULANMAYDI — mahalliy loopback HttpServer orqali,
// partiya raqamiga qarab TURLICHA kechikish bilan javob beriladi.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/models/foydalanuvchi.dart';
import 'package:kip_tarozi/screens/operator/operator_screen.dart';
import 'package:kip_tarozi/state/app_state.dart';

Map<String, dynamic> _partiyaJson({required int id, required int raqam}) => {
  'id': id,
  'mahsulot_id': 1,
  'mahsulot_kodi': 'tola',
  'mahsulot_nomi': 'Tola',
  'partiya_raqami': raqam,
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
};

void _javobYubor(HttpRequest req, int status, Object? tana) {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(tana));
  req.response.close();
}

/// `partiyaKechikishlari`: partiya_raqami -> shu so'rovga qo'shiladigan
/// sun'iy kechikish. Shu orqali "kim birinchi so'ralgan, kim oldin javob
/// bergan" tartibini nazorat qilamiz.
class _SoxtaServer {
  late HttpServer _server;
  final Map<int, Duration> partiyaKechikishlari;
  int _keyingiPartiyaId = 100;

  _SoxtaServer(this.partiyaKechikishlari);

  Future<int> ishgaTushirish() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      final yol = req.uri.path;
      if (req.method == 'GET' && yol == '/api/v1/mahsulotlar') {
        _javobYubor(req, 200, [
          {'id': 1, 'kod': 'tola', 'nomi': 'Tola'},
          {'id': 2, 'kod': 'lint', 'nomi': 'Lint'},
          {'id': 3, 'kod': 'pux', 'nomi': 'Pux'},
          {'id': 4, 'kod': 'ulyuk', 'nomi': 'Ulyuk'},
        ]);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/smena/holati') {
        _javobYubor(req, 200, {'smena': 'A', 'sana': '2026-09-01', 'mahsulotlar': []});
      } else if (req.method == 'GET' && yol == '/api/v1/shubhali-holatlar/bloklovchi') {
        _javobYubor(req, 200, null);
      } else if (req.method == 'GET' && yol == '/api/v1/partiyalar/ochiq') {
        _javobYubor(req, 200, []);
      } else if (req.method == 'GET' && yol == '/api/v1/kiplar/smena/royxat') {
        _javobYubor(req, 200, []);
      } else if (req.method == 'POST' && yol == '/api/v1/partiyalar') {
        final tana = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        final raqam = tana['partiya_raqami'] as int;
        final kechikish = partiyaKechikishlari[raqam] ?? Duration.zero;
        await Future.delayed(kechikish);
        _javobYubor(req, 200, _partiyaJson(id: _keyingiPartiyaId++, raqam: raqam));
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

Future<void> _kut(WidgetTester tester, {int marta = 6}) async {
  for (var i = 0; i < marta; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// Tugma so'rov davomida (_partiyaYuklanmoqda=true) o'chirilib qoladi — real
// hayotda race aynan TextField'ning "onSubmitted" (Enter tugmasi) orqali
// yuzaga keladi, chunki u shu bayroqni tekshirmaydi. Shuning uchun testda
// ham Enter orqali yuboramiz.
Future<void> _partiyaRaqaminiKiritish(WidgetTester tester, String raqam) async {
  await tester.enterText(find.byType(TextField).first, raqam);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.done);
}

void main() {
  testWidgets(
    'RACE: tez-tez partiya kiritilganda, oldingi (sekin) javob keyingisini bosib ketmasligi kerak',
    (tester) async {
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        // #5 SEKIN javob beradi, #8 TEZ — ya'ni #5 birinchi so'raladi, lekin
        // javobi #8'nikidan KEYIN keladi. Tuzatilmagan kodda oxirida #5
        // tanlangan bo'lib qolgan bo'lardi.
        final server = _SoxtaServer({5: const Duration(milliseconds: 600), 8: const Duration(milliseconds: 50)});
        final port = await server.ishgaTushirish();
        ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

        await tester.pumpWidget(_ekranQurish(_sinovHolati()));
        await _kut(tester, marta: 5);

        await tester.tap(find.text('Tola').first);
        await _kut(tester, marta: 3);

        await _partiyaRaqaminiKiritish(tester, '5');
        await tester.pump(const Duration(milliseconds: 20));
        await _partiyaRaqaminiKiritish(tester, '8');

        // Ikkala so'rov ham (eng sekini ham) javob berishi uchun yetarlicha kutamiz.
        await _kut(tester, marta: 10);

        await server.yopish();
      });

      expect(
        find.textContaining('Joriy partiya: #8'),
        findsOneWidget,
        reason: 'Oxirgi so\'ralgan partiya (#8) tanlangan bo\'lishi kerak',
      );
      expect(
        find.textContaining('Joriy partiya: #5'),
        findsNothing,
        reason: 'Eskirgan (stale) #5 javobi #8 ni bosib ketmasligi kerak',
      );
    },
  );

  testWidgets('Oddiy holat: race bo\'lmasa, partiya tanlash normal ishlashi kerak', (tester) async {
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      final server = _SoxtaServer({});
      final port = await server.ishgaTushirish();
      ApiClient.bazaUrl = 'http://127.0.0.1:$port/api/v1';

      await tester.pumpWidget(_ekranQurish(_sinovHolati()));
      await _kut(tester, marta: 5);

      await tester.tap(find.text('Tola').first);
      await _kut(tester, marta: 3);

      await _partiyaRaqaminiKiritish(tester, '5');
      await _kut(tester, marta: 5);

      await server.yopish();
    });

    expect(find.textContaining('Joriy partiya: #5'), findsOneWidget, reason: 'Oddiy holatda partiya #5 tanlanishi kerak');
  });
}
