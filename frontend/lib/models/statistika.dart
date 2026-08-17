class DavrJamlanmasi {
  final String davr;
  final String boshlanishSanasi;
  final String tugashSanasi;
  final List<MahsulotJamlanmasi> mahsulotlar;
  final int jamiSoni;
  final double jamiKg;

  DavrJamlanmasi({
    required this.davr,
    required this.boshlanishSanasi,
    required this.tugashSanasi,
    required this.mahsulotlar,
    required this.jamiSoni,
    required this.jamiKg,
  });

  factory DavrJamlanmasi.fromJson(Map<String, dynamic> j) => DavrJamlanmasi(
        davr: j['davr'],
        boshlanishSanasi: j['boshlanish_sanasi'],
        tugashSanasi: j['tugash_sanasi'],
        mahsulotlar: (j['mahsulotlar'] as List).map((e) => MahsulotJamlanmasi.fromJson(e)).toList(),
        jamiSoni: j['jami_soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
      );
}

class MahsulotJamlanmasi {
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int soni;
  final double jamiKg;

  MahsulotJamlanmasi({required this.mahsulotKodi, required this.mahsulotNomi, required this.soni, required this.jamiKg});

  factory MahsulotJamlanmasi.fromJson(Map<String, dynamic> j) => MahsulotJamlanmasi(
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        soni: j['soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
      );
}
