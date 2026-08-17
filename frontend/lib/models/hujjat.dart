class HujjatKip {
  final int id;
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int partiyaRaqami;
  final int kipRaqami;
  final double ogirlik;
  final String smena;
  final String operatorIsm;
  final DateTime vaqt;
  final String? suratYoli;
  final String holati;

  HujjatKip({
    required this.id,
    required this.mahsulotKodi,
    required this.mahsulotNomi,
    required this.partiyaRaqami,
    required this.kipRaqami,
    required this.ogirlik,
    required this.smena,
    required this.operatorIsm,
    required this.vaqt,
    this.suratYoli,
    required this.holati,
  });

  factory HujjatKip.fromJson(Map<String, dynamic> j) => HujjatKip(
        id: j['id'],
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        partiyaRaqami: j['partiya_raqami'],
        kipRaqami: j['kip_raqami'],
        ogirlik: (j['ogirlik'] as num).toDouble(),
        smena: j['smena'],
        operatorIsm: j['operator_ism'],
        vaqt: DateTime.parse(j['vaqt']),
        suratYoli: j['surat_yoli'],
        holati: j['holati'],
      );
}

class Sahifalangan<T> {
  final List<T> items;
  final int jami;
  final int sahifa;
  final int sahifaHajmi;

  Sahifalangan({required this.items, required this.jami, required this.sahifa, required this.sahifaHajmi});

  factory Sahifalangan.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) itemFromJson) =>
      Sahifalangan(
        items: (j['items'] as List).map((e) => itemFromJson(e)).toList(),
        jami: j['jami'],
        sahifa: j['sahifa'],
        sahifaHajmi: j['sahifa_hajmi'],
      );
}
