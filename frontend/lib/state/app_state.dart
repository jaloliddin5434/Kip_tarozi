import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../i18n/strings.dart';
import '../models/foydalanuvchi.dart';
import '../navigasiya_kalitlari.dart';
import '../services/offline_kip_navbati.dart';

class AppState extends ChangeNotifier {
  AppState() {
    // AUDIT TUZATISHI: markazlashgan "401 = avtomatik logout" — ApiClient
    // qaysi so'rovdan (istisnosiz) 401 olsa ham shu chaqiriladi.
    api.bir401SodirBoldi = _sessiyaMajburiyTugadi;
  }

  final ApiClient api = ApiClient();

  Foydalanuvchi? foydalanuvchi;
  ThemeMode temaRejimi = ThemeMode.light;
  Til til = Til.uz;

  String? moliyaviyToken;
  DateTime? moliyaviyTokenMuddati;

  Lokalizatsiya get lok => Lokalizatsiya(til);
  bool get kirilgan => foydalanuvchi != null && api.token != null;
  bool get moliyaviySessiyaAmalda =>
      moliyaviyToken != null && moliyaviyTokenMuddati != null && moliyaviyTokenMuddati!.isAfter(DateTime.now());

  Future<void> tiklash() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final temaNomi = prefs.getString('tema');
    final tilNomi = prefs.getString('til');

    if (temaNomi == 'dark') temaRejimi = ThemeMode.dark;
    if (tilNomi == 'ru') til = Til.ru;

    if (token != null) {
      api.token = token;
      try {
        final javob = await api.get('/auth/men');
        foydalanuvchi = Foydalanuvchi.fromJson(javob);
      } catch (_) {
        api.token = null;
        await prefs.remove('token');
      }
    }
    notifyListeners();
  }

  Future<void> kirish(String login, String parol) async {
    final javob = await api.post('/auth/login', tana: {'login': login, 'parol': parol});
    api.token = javob['access_token'];

    final men = await api.get('/auth/men');
    foydalanuvchi = Foydalanuvchi.fromJson(men);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', api.token!);
    // AUDIT TUZATISHI: navbatda shu FOYDALANUVCHIga tegishli (eski, endi
    // bekor qilingan/eskirgan tokenli) kutilayotgan offline yozuvlar bo'lsa —
    // yangi token bilan yangilaymiz, aks holda ular qayta login qilingandan
    // keyin ham abadiy eski (o'lik) token bilan 401 olib hech qachon
    // yuborilmay qolardi. Boshqa foydalanuvchiga tegishli yozuvlarga
    // tegilmaydi (JWT "sub" solishtiriladi) — smena almashinuvida noto'g'ri
    // operatorga bog'lanib qolmasligi uchun.
    await OfflineKipNavbati.yangiTokenBilanYangilash(api.token!);
    notifyListeners();
  }

  Future<void> moliyaviyParolOrnatish(String parol) async {
    await api.post('/moliyaviy/parolni-ornatish', tana: {'parol': parol});
  }

  Future<void> moliyaviyKirish(String parol) async {
    // sessiyaTekshiruvi:false — bu endpointda 401 "moliyaviy parol
    // noto'g'ri" degani, asosiy sessiya tugashini ANGLATMAYDI (ekranning
    // o'zi buni alohida, maxsus xabar bilan ko'rsatadi — pastga qarang
    // moliyaviy_kirish_screen.dart). Global logout ishga tushmasligi kerak.
    final javob = await api.post('/moliyaviy/kirish', tana: {'parol': parol}, sessiyaTekshiruvi: false);
    moliyaviyToken = javob['access_token'];
    moliyaviyTokenMuddati = DateTime.now().add(Duration(minutes: javob['muddat_daqiqa']));
    notifyListeners();
  }

  void moliyaviyChiqish() {
    moliyaviyToken = null;
    moliyaviyTokenMuddati = null;
    notifyListeners();
  }

  /// Moliyaviy-token bilan himoyalangan endpointlarga so'rov yuboradi. Token
  /// muddati tugagan/rad etilgan bo'lsa (401), sessiyani tozalab xatoni qayta
  /// uloqtiradi — chaqiruvchi ekran shu orqali kirish ekraniga qaytishi kerak.
  Future<dynamic> moliyaviyGet(String yol, {Map<String, dynamic>? query}) async {
    try {
      // sessiyaTekshiruvi:false — moliyaviy QO'SHIMCHA sessiyaning tugashi
      // asosiy login sessiyasini bekor qilmasligi kerak (pastda faqat
      // moliyaviyChiqish() chaqiriladi — to'liq logout emas).
      return await api.get(yol, query: query, tokenOverride: moliyaviyToken, sessiyaTekshiruvi: false);
    } on ApiException catch (e) {
      if (e.statusCode == 401) moliyaviyChiqish();
      rethrow;
    }
  }

  Future<void> chiqish() async {
    api.token = null;
    foydalanuvchi = null;
    moliyaviyToken = null;
    moliyaviyTokenMuddati = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }

  /// AUDIT TUZATISHI: `ApiClient`dan istisnosiz har qanday so'rovda 401
  /// kelganda (masalan admin operatorning tokenini bekor qilsa, yoki parol
  /// o'zgarsa) chaqiriladi. Joriy ekran nima bo'lishidan qat'i nazar — hatto
  /// "Kamera tasdiqlanmoqda" kabi ATAYLAB chiqish yo'lisiz
  /// (`PopScope(canPop: false)`) blokловчи dialog ochiq bo'lsa ham — uni
  /// yopib, sessiyani tozalab, login ekraniga qaytaradi va tushunarli xabar
  /// ko'rsatadi.
  void _sessiyaMajburiyTugadi() {
    if (!kirilgan) return;

    // Ochiq har qanday dialog (kamera-tasdiq kutish, "yuk saqlanmadi"
    // blokловчи oynasi va h.k.) — bular alohida Navigator route sifatida
    // asosiy ekran ustida turadi; ildiz marshrutgacha yopib tashlaymiz.
    navigatorKaliti.currentState?.popUntil((route) => route.isFirst);

    foydalanuvchi = null;
    api.token = null;
    moliyaviyToken = null;
    moliyaviyTokenMuddati = null;
    notifyListeners();

    unawaited(SharedPreferences.getInstance().then((prefs) => prefs.remove('token')));

    xabarKaliti.currentState?.showSnackBar(
      SnackBar(
        content: Text(lok.t('sessiya_tugadi_qayta_kiring')),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> temaniAlmashtirish() async {
    temaRejimi = temaRejimi == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tema', temaRejimi == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> tilniAlmashtirish() async {
    til = til == Til.uz ? Til.ru : Til.uz;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('til', til == Til.ru ? 'ru' : 'uz');
    notifyListeners();
  }
}
