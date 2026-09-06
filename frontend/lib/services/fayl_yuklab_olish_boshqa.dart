import 'dart:io';
import 'dart:typed_data';

/// Web BO'LMAGAN platformalarda (Windows/macOS/Linux desktop) baytlarni
/// foydalanuvchining "Downloads" (Yuklashlar) papkasiga real fayl sifatida
/// yozadi va yozilgan TO'LIQ yo'lni qaytaradi — chaqiruvchi ekran shu yo'lni
/// foydalanuvchiga ko'rsatadi ("... ga saqlandi").
///
/// Nega native "save dialog" emas, balki to'g'ridan-to'g'ri Downloads papkasi:
/// loyihada hali native fayl-tanlash paketi (file_picker) yo'q va uni qo'shish
/// har platformada alohida native kod/CMake sozlashini talab qiladi. Downloads
/// papkasiga yozish esa qo'shimcha paketsiz, faqat `dart:io` bilan ishonchli
/// bajariladi. Downloads papkasi topilmasa foydalanuvchi uy papkasiga,
/// u ham bo'lmasa vaqtinchalik papkaga tushadi.
///
/// Xatolik (ruxsat yo'q, disk to'la, yo'l noto'g'ri) JIMGINA yutilmaydi —
/// tegishli `FileSystemException` chaqiruvchiga qayta uloqtiriladi.
Future<String?> faylniSaqlash(Uint8List baytlar, String faylNomi) async {
  final papka = await _yuklashlarPapkasi();
  if (!await papka.exists()) {
    await papka.create(recursive: true);
  }

  final nom = _xavfsizFaylNomi(faylNomi);
  final yol = _bandBolmaganYol('${papka.path}${Platform.pathSeparator}$nom');

  final fayl = File(yol);
  await fayl.writeAsBytes(baytlar, flush: true);
  return fayl.path;
}

/// Joriy foydalanuvchining "Downloads" papkasi. Windows'da
/// `%USERPROFILE%\Downloads`, macOS/Linux'da `$HOME/Downloads`. Papka
/// bo'lmasa — uy papkasi, u ham bo'lmasa — tizim vaqtinchalik papkasi.
Future<Directory> _yuklashlarPapkasi() async {
  final env = Platform.environment;
  final uy = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  if (uy != null && uy.isNotEmpty) {
    final downloads = Directory('$uy${Platform.pathSeparator}Downloads');
    if (await downloads.exists()) return downloads;
    return Directory(uy);
  }
  return Directory.systemTemp;
}

/// Windows/macOS'da fayl nomida ishlatib bo'lmaydigan belgilarni
/// ( \ / : * ? " < > | va boshqaruv belgilari) pastki chiziq bilan
/// almashtiradi.
String _xavfsizFaylNomi(String nom) {
  final tozalangan = nom.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  return tozalangan.isEmpty ? 'fayl' : tozalangan;
}

/// Agar shu nomli fayl allaqachon mavjud bo'lsa, ustiga yozib yubormaslik
/// uchun "nom (1).xlsx", "nom (2).xlsx" ... ko'rinishida bo'sh nom tanlaydi.
String _bandBolmaganYol(String yol) {
  if (!File(yol).existsSync()) return yol;

  final nuqta = yol.lastIndexOf('.');
  final ajratgich = yol.lastIndexOf(Platform.pathSeparator);
  final kengaytmaBor = nuqta > ajratgich + 1; // "....xlsx" nomning ichida
  final asos = kengaytmaBor ? yol.substring(0, nuqta) : yol;
  final kengaytma = kengaytmaBor ? yol.substring(nuqta) : '';

  for (var i = 1; i < 1000; i++) {
    final nomzod = '$asos ($i)$kengaytma';
    if (!File(nomzod).existsSync()) return nomzod;
  }
  return yol; // amalda yetib kelmaydi
}
