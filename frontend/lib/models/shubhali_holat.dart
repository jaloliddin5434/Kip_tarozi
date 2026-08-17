class ShubhaliHolat {
  final int id;
  final DateTime vaqt;
  final String? smena;
  final double ogirlik;
  final String? suratYoli;
  final String holati;
  final bool tasdiqlangan;
  final int? koribChiqqanId;
  final DateTime? koribChiqilganVaqt;
  final String? koribChiqqanIsm;
  final String? operatorIsm;

  ShubhaliHolat({
    required this.id,
    required this.vaqt,
    this.smena,
    required this.ogirlik,
    this.suratYoli,
    required this.holati,
    required this.tasdiqlangan,
    this.koribChiqqanId,
    this.koribChiqilganVaqt,
    this.koribChiqqanIsm,
    this.operatorIsm,
  });

  factory ShubhaliHolat.fromJson(Map<String, dynamic> j) => ShubhaliHolat(
        id: j['id'],
        vaqt: DateTime.parse(j['vaqt']),
        smena: j['smena'],
        ogirlik: (j['ogirlik'] as num).toDouble(),
        suratYoli: j['surat_yoli'],
        holati: j['holati'],
        tasdiqlangan: j['tasdiqlangan'] ?? false,
        koribChiqqanId: j['korib_chiqqan_id'],
        koribChiqilganVaqt: j['korib_chiqilgan_vaqt'] == null ? null : DateTime.parse(j['korib_chiqilgan_vaqt']),
        koribChiqqanIsm: j['korib_chiqqan_ism'],
        operatorIsm: j['operator_ism'],
      );
}

class ShubhaliHolatStatistika {
  final Map<String, int> smenaBoyicha;

  ShubhaliHolatStatistika({required this.smenaBoyicha});

  factory ShubhaliHolatStatistika.fromJson(Map<String, dynamic> j) => ShubhaliHolatStatistika(
        smenaBoyicha: (j['smena_boyicha'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
      );
}
