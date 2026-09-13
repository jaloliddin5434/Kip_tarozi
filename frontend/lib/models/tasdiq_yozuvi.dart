/// Admin "tasdiqlash/rad etish" navbati ko'rinishidagi ekranlar (kamera-tasdiq
/// so'rovlari, kip-to'g'rilash zayavkalari) uchun umumiy interfeys — bular
/// ikkalasi ham bir xil holat-mashinasiga ega (kutilmoqda -> tasdiqlangan
/// yoki rad_etilgan), shuning uchun `widgets/tasdiq_royxati_ekrani.dart`
/// generic ekrani shu orqali ishlaydi.
abstract interface class TasdiqYozuvi {
  int get id;
  String get holati; // kutilmoqda | tasdiqlangan | rad_etilgan
  bool get kutilmoqda;
  String? get halQilganIsm;
  String? get halQilishManbasi;
}
