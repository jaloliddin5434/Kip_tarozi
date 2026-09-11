/// `/media/kip-surat/...` endpointi (audit tuzatishidan keyin) autentifikatsiya
/// talab qiladi — oddiy `Image.network(url)` endi 401 qaytaradi. Shu funksiya
/// `Image.network`ning `headers` parametriga qo'shiladigan `Authorization`
/// sarlavhasini yasaydi.
Map<String, String>? suratSarlavhalari(String? token) {
  if (token == null || token.isEmpty) return null;
  return {'Authorization': 'Bearer $token'};
}
