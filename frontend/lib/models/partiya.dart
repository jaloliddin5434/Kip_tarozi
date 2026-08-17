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
  final String? xaridor;
  final String? nakladnoyRaqami;

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
    this.xaridor,
    this.nakladnoyRaqami,
  });

  factory Partiya.fromJson(Map<String, dynamic> j) => Partiya(
        id: j['id'],
        mahsulotId: j['mahsulot_id'],
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        partiyaRaqami: j['partiya_raqami'],
        holati: j['holati'],
        yaratilganVaqt: DateTime.parse(j['yaratilgan_vaqt']),
        yopilganVaqt: j['yopilgan_vaqt'] == null ? null : DateTime.parse(j['yopilgan_vaqt']),
        kipSoni: j['kip_soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
        xaridor: j['xaridor'],
        nakladnoyRaqami: j['nakladnoy_raqami'],
      );
}
