class Kip {
  final int id;
  final String mijozId;
  final int partiyaId;
  final int kipRaqami;
  final double ogirlik;
  final String smena;
  final DateTime vaqt;
  final String holati;
  final int? stansiyaId;

  Kip({
    required this.id,
    required this.mijozId,
    required this.partiyaId,
    required this.kipRaqami,
    required this.ogirlik,
    required this.smena,
    required this.vaqt,
    required this.holati,
    this.stansiyaId,
  });

  factory Kip.fromJson(Map<String, dynamic> j) => Kip(
        id: j['id'],
        mijozId: j['mijoz_id'],
        partiyaId: j['partiya_id'],
        kipRaqami: j['kip_raqami'],
        ogirlik: (j['ogirlik'] as num).toDouble(),
        smena: j['smena'],
        vaqt: DateTime.parse(j['vaqt']),
        holati: j['holati'],
        stansiyaId: j['stansiya_id'],
      );
}
