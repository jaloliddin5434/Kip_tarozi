import 'tasdiq_yozuvi.dart';

/// "Kamera ishlamasa — Admin ruxsati" oqimi. Kamera sozlangan-u surat ololmaganda
/// backend kipni saqlamaydi; shu so'rov yaratiladi va Admin (panel yoki Telegram
/// tugmasi orqali) tasdiqlaguncha operator bloklanadi.
class KameraTasdiqSorovi implements TasdiqYozuvi {
  @override
  final int id;
  final DateTime vaqt;
  final String smena;
  final double ogirlik;
  final String mahsulotNomi;
  final int partiyaRaqami;
  final String operatorIsm;
  @override
  final String holati; // kutilmoqda | tasdiqlangan | rad_etilgan
  final int? kipId;
  final DateTime? halQilinganVaqt;
  @override
  final String? halQilganIsm;
  @override
  final String? halQilishManbasi;
  final String? izoh;
  // AUDIT TUZATISHI: shu partiyada yaqin vaqtda/og'irlikda BOSHQA (saqlangan
  // kip yoki hal qilinmagan/tasdiqlangan boshqa so'rov) mavjudligi haqida
  // ogohlantirish — faqat vizual, hech narsani avtomatik bloklamaydi.
  final bool dublikatShubhasi;

  KameraTasdiqSorovi({
    required this.id,
    required this.vaqt,
    required this.smena,
    required this.ogirlik,
    required this.mahsulotNomi,
    required this.partiyaRaqami,
    required this.operatorIsm,
    required this.holati,
    this.kipId,
    this.halQilinganVaqt,
    this.halQilganIsm,
    this.halQilishManbasi,
    this.izoh,
    this.dublikatShubhasi = false,
  });

  @override
  bool get kutilmoqda => holati == 'kutilmoqda';

  factory KameraTasdiqSorovi.fromJson(Map<String, dynamic> j) => KameraTasdiqSorovi(
        id: j['id'],
        vaqt: DateTime.parse(j['vaqt']),
        smena: j['smena'],
        ogirlik: (j['ogirlik'] as num).toDouble(),
        mahsulotNomi: j['mahsulot_nomi'],
        partiyaRaqami: j['partiya_raqami'],
        operatorIsm: j['operator_ism'],
        holati: j['holati'],
        kipId: j['kip_id'],
        halQilinganVaqt: j['hal_qilingan_vaqt'] == null ? null : DateTime.parse(j['hal_qilingan_vaqt']),
        halQilganIsm: j['hal_qilgan_ism'],
        halQilishManbasi: j['hal_qilish_manbasi'],
        izoh: j['izoh'],
        dublikatShubhasi: j['dublikat_shubhasi'] == true,
      );
}

/// `GET /kamera-tasdiq/{id}/holat` javobi (operator polling qiladi).
class KameraTasdiqHolat {
  final int id;
  final String holati;
  final int? kipId;
  final String? izoh;

  KameraTasdiqHolat({required this.id, required this.holati, this.kipId, this.izoh});

  factory KameraTasdiqHolat.fromJson(Map<String, dynamic> j) => KameraTasdiqHolat(
        id: j['id'],
        holati: j['holati'],
        kipId: j['kip_id'],
        izoh: j['izoh'],
      );
}
