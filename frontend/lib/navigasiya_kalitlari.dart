import 'package:flutter/material.dart';

/// Butun ilova uchun global Navigator/ScaffoldMessenger kalitlari.
///
/// `ApiClient` darajasida sodir bo'ladigan 401 (sessiya tugashi/bekor
/// qilinishi) hodisasida, joriy ekran qanday bo'lishidan qat'i nazar
/// (operator, admin, hatto "Kamera tasdiqlanmoqda" kabi ATAYLAB
/// chiqish-yo'lisiz — `PopScope(canPop: false)` — blokловчи dialog ochiq
/// bo'lsa ham), login ekraniga qaytarish va xabar ko'rsatish uchun
/// ishlatiladi. `AppState` (oddiy `ChangeNotifier`, `BuildContext`ga ega
/// emas) shu kalitlar orqali Navigator/ScaffoldMessenger'ga murojaat qiladi.
final GlobalKey<NavigatorState> navigatorKaliti = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> xabarKaliti = GlobalKey<ScaffoldMessengerState>();
