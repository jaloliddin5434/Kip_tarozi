import 'smena_holati.dart';

class AgentHolati {
  final bool ulangan;
  final String? oxirgiXato;
  final String antiOgirlikHolati;
  final int navbatUzunligi;
  final bool yangimi;

  AgentHolati({
    required this.ulangan,
    this.oxirgiXato,
    required this.antiOgirlikHolati,
    required this.navbatUzunligi,
    required this.yangimi,
  });

  factory AgentHolati.fromJson(Map<String, dynamic> j) => AgentHolati(
        ulangan: j['ulangan'],
        oxirgiXato: j['oxirgi_xato'],
        antiOgirlikHolati: j['anti_ogirlik_holati'],
        navbatUzunligi: j['navbat_uzunligi'],
        yangimi: j['yangimi'],
      );
}

class SmenaJamlanmasi {
  final String smena;
  final int soni;
  final double jamiKg;

  SmenaJamlanmasi({required this.smena, required this.soni, required this.jamiKg});

  factory SmenaJamlanmasi.fromJson(Map<String, dynamic> j) => SmenaJamlanmasi(
        smena: j['smena'],
        soni: j['soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
      );
}

class Dashboard {
  final String davr;
  final String boshlanishSanasi;
  final String tugashSanasi;
  final List<MahsulotBoyichaHolat> mahsulotlar;
  final int jamiSoni;
  final double jamiKg;
  final List<SmenaJamlanmasi> smenalar;
  final int ochiqPartiyalarSoni;
  final int tasdiqlanmaganShubhaliHolatlarSoni;
  final AgentHolati? agentHolati;

  Dashboard({
    required this.davr,
    required this.boshlanishSanasi,
    required this.tugashSanasi,
    required this.mahsulotlar,
    required this.jamiSoni,
    required this.jamiKg,
    required this.smenalar,
    required this.ochiqPartiyalarSoni,
    required this.tasdiqlanmaganShubhaliHolatlarSoni,
    this.agentHolati,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        davr: j['davr'],
        boshlanishSanasi: j['boshlanish_sanasi'],
        tugashSanasi: j['tugash_sanasi'],
        mahsulotlar: (j['mahsulotlar'] as List).map((e) => MahsulotBoyichaHolat.fromJson(e)).toList(),
        jamiSoni: j['jami_soni'],
        jamiKg: (j['jami_kg'] as num).toDouble(),
        smenalar: (j['smenalar'] as List).map((e) => SmenaJamlanmasi.fromJson(e)).toList(),
        ochiqPartiyalarSoni: j['ochiq_partiyalar_soni'],
        tasdiqlanmaganShubhaliHolatlarSoni: j['tasdiqlanmagan_shubhali_holatlar_soni'],
        agentHolati: j['agent_holati'] == null ? null : AgentHolati.fromJson(j['agent_holati']),
      );
}
