import 'dart:io';
import 'dart:typed_data';

/// Web BO'LMAGAN platformalar (Windows/macOS/Linux desktop) — offline paytda
/// LAN kamerasidan olingan JPEG'ni operator kompyuterida saqlaydi, keyin
/// sinxronda backend'ga yuklab, o'chiradi.
///
/// Papka: `%USERPROFILE%\.kip_tarozi\offline_suratlar\` (Windows) yoki
/// `$HOME/.kip_tarozi/offline_suratlar/`. Uy papkasi topilmasa — tizim
/// vaqtinchalik papkasi. Fayl nomi = `<mijoz_id>.jpg` (bitta kip = bitta fayl).

Directory _papka() {
  final env = Platform.environment;
  final uy = Platform.isWindows ? env['USERPROFILE'] : env['HOME'];
  final asos = (uy != null && uy.isNotEmpty) ? Directory(uy) : Directory.systemTemp;
  return Directory('${asos.path}${Platform.pathSeparator}.kip_tarozi'
      '${Platform.pathSeparator}offline_suratlar');
}

String _yol(String mijozId) {
  final xavfsiz = mijozId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return '${_papka().path}${Platform.pathSeparator}$xavfsiz.jpg';
}

/// Baytlarni saqlaydi, to'liq yo'lni qaytaradi. Xatolik bo'lsa — null
/// (surat ixtiyoriy, kip baribir navbatga tushadi).
Future<String?> suratniSaqla(Uint8List baytlar, String mijozId) async {
  try {
    final papka = _papka();
    if (!await papka.exists()) await papka.create(recursive: true);
    final fayl = File(_yol(mijozId));
    await fayl.writeAsBytes(baytlar, flush: true);
    return fayl.path;
  } catch (_) {
    return null;
  }
}

/// Saqlangan suratni o'qiydi. Fayl yo'q/o'chirilgan bo'lsa — null.
Future<Uint8List?> suratniOqi(String yol) async {
  try {
    final fayl = File(yol);
    if (!await fayl.exists()) return null;
    return await fayl.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Yuklab bo'lingach suratni o'chiradi (xatoni yutadi).
Future<void> suratniOchir(String yol) async {
  try {
    final fayl = File(yol);
    if (await fayl.exists()) await fayl.delete();
  } catch (_) {}
}
