// Hujjatlar ekrani — ikkita UX yaxshilash:
// 1) "Kunlik/Haftalik/Oylik/Mavsum" tezkor davr tugmalari — bosilganda
//    backenddagi /hujjatlar/davr-oraligi orqali hisoblangan sana_dan/
//    sana_gacha /hujjatlar/kiplar so'roviga to'g'ri uzatilishi.
// 2) "Partiya raqami" va "Kip №" qidiruv maydonlari — faqat raqam qabul
//    qilishi va backendga mos parametrlar bilan yuborilishi, natijada
//    aynan bitta kip topilishi.
//
// Mahalliy loopback HttpServer orqali soxta javoblar bilan, HAQIQIY
// backendga ulanmasdan sinaydi (qarang tasdiqlash_tarixi_test.dart bilan
// bir xil naqsh).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/api/api_client.dart';
import 'package:kip_tarozi/main.dart';
import 'package:kip_tarozi/screens/admin/hujjatlar_screen.dart';
import 'package:kip_tarozi/widgets/kalendar_vidjeti.dart';

final _bugun = DateTime.now();

Map<String, dynamic> _kip({
  required int id,
  required String mahsulotKodi,
  required String mahsulotNomi,
  required int partiyaRaqami,
  required int kipRaqami,
  required double ogirlik,
  required String operatorIsm,
}) => {
  'id': id,
  'mahsulot_kodi': mahsulotKodi,
  'mahsulot_nomi': mahsulotNomi,
  'partiya_id': 1,
  'partiya_raqami': partiyaRaqami,
  'kip_raqami': kipRaqami,
  'ogirlik': ogirlik,
  'smena': 'A',
  'operator_id': 1,
  'operator_ism': operatorIsm,
  'vaqt': DateTime.now().toUtc().toIso8601String(),
  'surat_yoli': null,
  'holati': 'aktiv',
};

Future<HttpServer> _soxtaServerYarat({required List<Map<String, String>> qilinganSorovlar}) async {
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
        'davr': 'kunlik', 'boshlanish_sanasi': '2026-09-19', 'tugash_sanasi': '2026-09-19',
        'mahsulotlar': [], 'jami_soni': 0, 'jami_kg': 0.0, 'smenalar': [],
        'ochiq_partiyalar_soni': 0, 'tasdiqlanmagan_shubhali_holatlar_soni': 0, 'agent_holati': null,
      };
    } else if (yol == '/api/v1/hujjatlar/davr-oraligi') {
      final davr = req.uri.queryParameters['davr'];
      final oraliqlar = {
        'kunlik': ['2026-09-19', '2026-09-19'],
        'haftalik': ['2026-09-14', '2026-09-20'],
        'oylik': ['2026-08-01', '2026-08-31'],
        'mavsum': ['2025-09-01', '2026-09-19'],
      };
      final oraliq = oraliqlar[davr]!;
      tana = {'davr': davr, 'sana_dan': oraliq[0], 'sana_gacha': oraliq[1]};
    } else if (yol == '/api/v1/hujjatlar/kiplar') {
      qilinganSorovlar.add(req.uri.queryParameters);
      final q = req.uri.queryParameters;
      if (q['partiya_raqami'] == '55' && q['kip_raqami'] == '11') {
        // 2-qism: mahsulot+partiya+kip kombinatsiyasi — AYNAN bitta kip.
        tana = {
          'items': [
            _kip(
              id: 501, mahsulotKodi: 'tola', mahsulotNomi: 'Tola',
              partiyaRaqami: 55, kipRaqami: 11, ogirlik: 132.5, operatorIsm: 'Yagona Operator',
            ),
          ],
          'jami': 1, 'sahifa': 1, 'sahifa_hajmi': 30,
        };
      } else if (q['sana_dan'] == '2026-08-01' && q['sana_gacha'] == '2026-08-31') {
        // 1-qism: "Oylik" davr tugmasi bosilgandan keyingi oraliq.
        tana = {
          'items': [
            _kip(id: 1, mahsulotKodi: 'tola', mahsulotNomi: 'Tola', partiyaRaqami: 60, kipRaqami: 1, ogirlik: 100.0, operatorIsm: 'Oylik Operator 1'),
            _kip(id: 2, mahsulotKodi: 'tola', mahsulotNomi: 'Tola', partiyaRaqami: 60, kipRaqami: 2, ogirlik: 101.0, operatorIsm: 'Oylik Operator 2'),
            _kip(id: 3, mahsulotKodi: 'lint', mahsulotNomi: 'Lint', partiyaRaqami: 61, kipRaqami: 1, ogirlik: 90.0, operatorIsm: 'Oylik Operator 3'),
          ],
          'jami': 3, 'sahifa': 1, 'sahifa_hajmi': 30,
        };
      } else {
        // Standart (boshlang'ich, "bugun") holat.
        tana = {'items': [], 'jami': 0, 'sahifa': 1, 'sahifa_hajmi': 30};
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

/// Dashboard ekrani ("so'nggi hodisalar" paneli) ham xuddi shu
/// `/hujjatlar/kiplar` endpointiga (`holati=aktiv`, `sahifa_hajmi=500` bilan)
/// mustaqil so'rov yuboradi — IndexedStack barcha admin sahifalarini bir
/// vaqtda qurgani uchun bu Hujjatlar ekranining o'z so'rovlari bilan
/// aralashib ketishi mumkin. Shuning uchun Hujjatlar ekraniga xos so'rovlar
/// (har doim `sahifa_hajmi=30`) alohida ajratiladi.
Map<String, String>? _oxirgiHujjatlarSorovi(List<Map<String, String>> hammasi) {
  final hujjatlarnikilar = hammasi.where((s) => s['sahifa_hajmi'] == '30');
  return hujjatlarnikilar.isEmpty ? null : hujjatlarnikilar.last;
}

void main() {
  testWidgets(
    'Hujjatlar: davr tugmalari to\'g\'ri sana_dan/sana_gacha yuboradi',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      late HttpServer server;
      final qilinganSorovlar = <Map<String, String>>[];

      await tester.runAsync(() async {
        HttpOverrides.global = null;
        server = await _soxtaServerYarat(qilinganSorovlar: qilinganSorovlar);
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

        await tester.tap(find.text('Hujjatlar'));
        await _kut(tester, marta: 4);

        // --- 1-QISM: "Oylik" davr tugmasi ---
        // Bosishdan oldin — kalendar orqali qo'lda sana tanlash imkoniyati
        // hamon mavjud (tugmalar buni olib tashlamaydi), tekshirib o'tamiz.
        expect(find.text('Sana dan'), findsNothing); // "bugun" allaqachon tanlangan, sana ko'rsatilmoqda
        expect(find.widgetWithText(OutlinedButton, 'Oylik'), findsOneWidget);

        await tester.tap(find.text('Oylik'));
        await _kut(tester, marta: 5);

        // Backendga /hujjatlar/davr-oraligi orqali hisoblangan oraliq
        // (2026-08-01 — 2026-08-31) /hujjatlar/kiplar so'roviga yetib borgan.
        final oxirgiSorov = _oxirgiHujjatlarSorovi(qilinganSorovlar);
        expect(oxirgiSorov?['sana_dan'], '2026-08-01');
        expect(oxirgiSorov?['sana_gacha'], '2026-08-31');

        // Natija — mos ravishda filtrlangan (3 ta yozuv), va "Sana dan"/
        // "Sana gacha" tugmalari ham yangi qiymatlarni ko'rsatadi (mavjud
        // qo'lda sana tanlash imkoniyati bilan izchil).
        expect(find.textContaining('Jami: 3'), findsOneWidget);
        expect(find.text('2026-08-01'), findsOneWidget);
        expect(find.text('2026-08-31'), findsOneWidget);
        expect(find.textContaining('Oylik Operator 1'), findsOneWidget);

        // "Oylik" tugmasi endi "tanlangan" (ElevatedButton) holatida.
        expect(find.ancestor(of: find.text('Oylik'), matching: find.byType(ElevatedButton)), findsOneWidget);

        // Mavjud ALOHIDA sana tanlash (kalendar) imkoniyati bu tugmalar bilan
        // OLIB TASHLANMAGAN — qo'lda kun tanlansa hamon ishlaydi, va davr
        // tugmasi "tanlangan" holatidan chiqadi (mustaqil, qo'shimcha variant).
        final bugunKatakchasi = find.descendant(
          of: find.byType(KalendarVidjeti),
          matching: find.text('${_bugun.day}'),
        );
        expect(bugunKatakchasi, findsOneWidget);
        await tester.tap(bugunKatakchasi);
        await _kut(tester, marta: 4);

        expect(find.ancestor(of: find.text('Oylik'), matching: find.byType(ElevatedButton)), findsNothing);
        expect(find.ancestor(of: find.text('Oylik'), matching: find.byType(OutlinedButton)), findsOneWidget);

        // --- 2-QISM: Partiya raqami + Kip № qidiruv maydonlari ---
        final hujjatlarOstida = find.descendant(
          of: find.byType(HujjatlarEkrani),
          matching: find.byType(TextField),
        );
        // Tartib: Qidiruv(0), Partiya raqami(1), Kip №(2)
        final partiyaMaydoni = hujjatlarOstida.at(1);
        final kipMaydoni = hujjatlarOstida.at(2);

        // Raqam bo'lmagan belgilar rad etilishi kerak (FilteringTextInputFormatter.digitsOnly).
        await tester.enterText(partiyaMaydoni, 'ab55cd');
        await tester.pump();
        expect(tester.widget<TextField>(partiyaMaydoni).controller!.text, '55');

        await tester.enterText(kipMaydoni, '11x');
        await _kut(tester, marta: 5); // 500ms debounce + javob

        final sonliSorov = _oxirgiHujjatlarSorovi(qilinganSorovlar);
        expect(sonliSorov?['partiya_raqami'], '55');
        expect(sonliSorov?['kip_raqami'], '11');

        // Aynan bitta mos kip ko'rinadi.
        expect(find.textContaining('Yagona Operator'), findsOneWidget);
        expect(find.textContaining('Jami: 1'), findsOneWidget);
        expect(find.textContaining('Oylik Operator 1'), findsNothing);

        await server.close(force: true);
      });
    },
  );
}
