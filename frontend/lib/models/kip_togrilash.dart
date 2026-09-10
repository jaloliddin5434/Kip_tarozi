/// Operator "Smena tarixi" ro'yxatidagi bir kip uchun mahsulot/partiya
/// noto'g'ri tanlanganini bildirib, to'g'rilash so'ragan zayavka. Admin
/// (panel yoki Telegram tugmasi orqali) tasdiqlaguncha kip o'zgarishsiz qoladi.
class KipTogrilashZayavkasi {
  final int id;
  final DateTime vaqt;
  final int kipId;
  final int kipRaqami;
  final String operatorIsm;
  final String eskiMahsulotNomi;
  final int eskiPartiyaRaqami;
  final String yangiMahsulotNomi;
  final int yangiPartiyaRaqami;
  final String sabab;
  final String holati; // kutilmoqda | tasdiqlangan | rad_etilgan
  final DateTime? halQilinganVaqt;
  final String? halQilganIsm;
  final String? halQilishManbasi;
  final String? izoh;

  KipTogrilashZayavkasi({
    required this.id,
    required this.vaqt,
    required this.kipId,
    required this.kipRaqami,
    required this.operatorIsm,
    required this.eskiMahsulotNomi,
    required this.eskiPartiyaRaqami,
    required this.yangiMahsulotNomi,
    required this.yangiPartiyaRaqami,
    required this.sabab,
    required this.holati,
    this.halQilinganVaqt,
    this.halQilganIsm,
    this.halQilishManbasi,
    this.izoh,
  });

  bool get kutilmoqda => holati == 'kutilmoqda';

  factory KipTogrilashZayavkasi.fromJson(Map<String, dynamic> j) => KipTogrilashZayavkasi(
        id: j['id'],
        vaqt: DateTime.parse(j['vaqt']),
        kipId: j['kip_id'],
        kipRaqami: j['kip_raqami'],
        operatorIsm: j['operator_ism'],
        eskiMahsulotNomi: j['eski_mahsulot_nomi'],
        eskiPartiyaRaqami: j['eski_partiya_raqami'],
        yangiMahsulotNomi: j['yangi_mahsulot_nomi'],
        yangiPartiyaRaqami: j['yangi_partiya_raqami'],
        sabab: j['sabab'],
        holati: j['holati'],
        halQilinganVaqt: j['hal_qilingan_vaqt'] == null ? null : DateTime.parse(j['hal_qilingan_vaqt']),
        halQilganIsm: j['hal_qilgan_ism'],
        halQilishManbasi: j['hal_qilish_manbasi'],
        izoh: j['izoh'],
      );
}
