class Partiya {
  final int id;
  final int mahsulotId;
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int partiyaRaqami;
  final String holati; // ochiq | yopiq | sotilgan
  final DateTime yaratilganVaqt;
  final DateTime? yopilganVaqt;
  final int kipSoni;
  final double jamiKg;
  final DateTime? sotuvSanasi;
  final String? xaridor;
  final String? nakladnoyRaqami;
  final String? sort;
  final double? uramaBilanVazn;
  final double? uramaVazni;
  final double? sofVazn;
  final double? kondicionVazni;

  Partiya({
    required this.id,
    required this.mahsulotId,
    required this.mahsulotKodi,
    required this.mahsulotNomi,
    required this.partiyaRaqami,
    required this.holati,
    required this.yaratilganVaqt,
    this.yopilganVaqt,
    required this.kipSoni,
    required this.jamiKg,
    this.sotuvSanasi,
    this.xaridor,
    this.nakladnoyRaqami,
    this.sort,
    this.uramaBilanVazn,
    this.uramaVazni,
    this.sofVazn,
    this.kondicionVazni,
  });

  factory Partiya.fromJson(Map<String, dynamic> j) => Partiya(
    id: j['id'],
    mahsulotId: j['mahsulot_id'],
    mahsulotKodi: j['mahsulot_kodi'],
    mahsulotNomi: j['mahsulot_nomi'],
    partiyaRaqami: j['partiya_raqami'],
    holati: j['holati'],
    yaratilganVaqt: DateTime.parse(j['yaratilgan_vaqt']),
    yopilganVaqt: j['yopilgan_vaqt'] == null
        ? null
        : DateTime.parse(j['yopilgan_vaqt']),
    kipSoni: j['kip_soni'],
    jamiKg: (j['jami_kg'] as num).toDouble(),
    sotuvSanasi: j['sotuv_sanasi'] == null ? null : DateTime.parse(j['sotuv_sanasi']),
    xaridor: j['xaridor'],
    nakladnoyRaqami: j['nakladnoy_raqami'],
    sort: j['sort'],
    uramaBilanVazn: (j['urama_bilan_vazn'] as num?)?.toDouble(),
    uramaVazni: (j['urama_vazni'] as num?)?.toDouble(),
    sofVazn: (j['sof_vazn'] as num?)?.toDouble(),
    kondicionVazni: (j['kondicion_vazni'] as num?)?.toDouble(),
  );
}
