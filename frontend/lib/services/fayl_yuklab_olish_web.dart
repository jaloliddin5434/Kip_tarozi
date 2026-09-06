import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Xotiradagi baytlarni brauzer orqali "Saqlash" (download) sifatida
/// beradi — vaqtinchalik Blob URL yaratib, ko'rinmas <a download> havolasini
/// avtomatik bosadi, so'ng URL'ni bekor qiladi.
///
/// `null` qaytaradi: brauzer faylni qayerga saqlashni o'zi hal qiladi
/// (odatda "Downloads"), aniq yo'lni JavaScript bila olmaydi — chaqiruvchi
/// shunga qarab umumiy "yuklab olindi" xabarini ko'rsatadi.
Future<String?> faylniSaqlash(Uint8List baytlar, String faylNomi) async {
  final blob = web.Blob([baytlar.toJS].toJS);
  final url = web.URL.createObjectURL(blob);

  final havola = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = faylNomi
    ..style.display = 'none';
  web.document.body!.appendChild(havola);
  havola.click();
  havola.remove();

  web.URL.revokeObjectURL(url);
  return null;
}
