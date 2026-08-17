class MahsulotBoyichaHolat {
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int soni;
  final double jamiKg;

  MahsulotBoyichaHolat({required this.mahsulotKodi, required this.mahsulotNomi, required this.soni, required this.jamiKg});

  factory MahsulotBoyichaHolat.fromJson(Map<String, dynamic> j) => MahsulotBoyichaHolat(
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        soni: j['soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
      );
}

class SmenaHolati {
  final String smena;
  final String sana;
  final List<MahsulotBoyichaHolat> mahsulotlar;

  SmenaHolati({required this.smena, required this.sana, required this.mahsulotlar});

  factory SmenaHolati.fromJson(Map<String, dynamic> j) => SmenaHolati(
        smena: j['smena'],
        sana: j['sana'],
        mahsulotlar: (j['mahsulotlar'] as List).map((e) => MahsulotBoyichaHolat.fromJson(e)).toList(),
      );
}
