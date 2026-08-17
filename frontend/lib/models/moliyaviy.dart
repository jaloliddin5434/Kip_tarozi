class UzexNarx {
  final String mahsulotKodi;
  final String mahsulotNomi;
  final double narxSom;
  final DateTime yangilanganVaqt;

  UzexNarx({
    required this.mahsulotKodi,
    required this.mahsulotNomi,
    required this.narxSom,
    required this.yangilanganVaqt,
  });

  factory UzexNarx.fromJson(Map<String, dynamic> j) => UzexNarx(
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        narxSom: (j['narx_som'] as num).toDouble(),
        yangilanganVaqt: DateTime.parse(j['yangilangan_vaqt']),
      );
}

class MoliyaviyMahsulotHisoboti {
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int partiyalarSoni;
  final double jamiSofVazn;
  final double jamiSumma;

  MoliyaviyMahsulotHisoboti({
    required this.mahsulotKodi,
    required this.mahsulotNomi,
    required this.partiyalarSoni,
    required this.jamiSofVazn,
    required this.jamiSumma,
  });

  factory MoliyaviyMahsulotHisoboti.fromJson(Map<String, dynamic> j) => MoliyaviyMahsulotHisoboti(
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        partiyalarSoni: j['partiyalar_soni'],
        jamiSofVazn: (j['jami_sof_vazn'] as num).toDouble(),
        jamiSumma: (j['jami_summa'] as num).toDouble(),
      );
}

class MoliyaviyHisobot {
  final String davr;
  final String boshlanishSanasi;
  final String tugashSanasi;
  final List<MoliyaviyMahsulotHisoboti> mahsulotlar;
  final double jamiSumma;

  MoliyaviyHisobot({
    required this.davr,
    required this.boshlanishSanasi,
    required this.tugashSanasi,
    required this.mahsulotlar,
    required this.jamiSumma,
  });

  factory MoliyaviyHisobot.fromJson(Map<String, dynamic> j) => MoliyaviyHisobot(
        davr: j['davr'],
        boshlanishSanasi: j['boshlanish_sanasi'],
        tugashSanasi: j['tugash_sanasi'],
        mahsulotlar: (j['mahsulotlar'] as List).map((e) => MoliyaviyMahsulotHisoboti.fromJson(e)).toList(),
        jamiSumma: (j['jami_summa'] as num).toDouble(),
      );
}
