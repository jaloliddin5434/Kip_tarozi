import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../i18n/strings.dart';
import '../models/foydalanuvchi.dart';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  Foydalanuvchi? foydalanuvchi;
  ThemeMode temaRejimi = ThemeMode.light;
  Til til = Til.uz;

  Lokalizatsiya get lok => Lokalizatsiya(til);
  bool get kirilgan => foydalanuvchi != null && api.token != null;

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
    notifyListeners();
  }

  Future<void> chiqish() async {
    api.token = null;
    foydalanuvchi = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
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
