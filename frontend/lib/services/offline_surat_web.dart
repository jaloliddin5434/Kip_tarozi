import 'dart:typed_data';

/// Web build'da offline surat saqlash qo'llab-quvvatlanmaydi (fayl tizimi yo'q).
/// Barcha funksiyalar no-op — kip suratsiz navbatga tushadi (funksionallik
/// buzilmaydi). Ishlab chiqarishda operator ilovasi Windows desktop build'da.
Future<String?> suratniSaqla(Uint8List baytlar, String mijozId) async => null;

Future<Uint8List?> suratniOqi(String yol) async => null;

Future<void> suratniOchir(String yol) async {}
