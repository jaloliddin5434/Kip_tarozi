/// Statistika ekranidagi "Rekord" paneli uchun (GET /statistika/rekordlar).
/// eng_yaxshi_smena / eng_yaxshi_operator tanlangan davr bo'yicha,
/// eng_yuqori_kunlik_yigim esa doim barcha vaqt bo'yicha.
class Rekordlar {
  final RekordSmena? engYaxshiSmena;
  final RekordOperator? engYaxshiOperator;
  final RekordKun? engYuqoriKunlikYigim;

  Rekordlar({this.engYaxshiSmena, this.engYaxshiOperator, this.engYuqoriKunlikYigim});

  factory Rekordlar.fromJson(Map<String, dynamic> j) => Rekordlar(
        engYaxshiSmena: j['eng_yaxshi_smena'] == null ? null : RekordSmena.fromJson(j['eng_yaxshi_smena']),
        engYaxshiOperator:
            j['eng_yaxshi_operator'] == null ? null : RekordOperator.fromJson(j['eng_yaxshi_operator']),
        engYuqoriKunlikYigim:
            j['eng_yuqori_kunlik_yigim'] == null ? null : RekordKun.fromJson(j['eng_yuqori_kunlik_yigim']),
      );
}

class RekordSmena {
  final String smena;
  final double jamiKg;

  RekordSmena({required this.smena, required this.jamiKg});

  factory RekordSmena.fromJson(Map<String, dynamic> j) =>
      RekordSmena(smena: j['smena'], jamiKg: (j['jami_kg'] as num).toDouble());
}

class RekordOperator {
  final int operatorId;
  final String ism;
  final String login;
  final int soni;

  RekordOperator({required this.operatorId, required this.ism, required this.login, required this.soni});

  factory RekordOperator.fromJson(Map<String, dynamic> j) => RekordOperator(
        operatorId: j['operator_id'],
        ism: j['ism'],
        login: j['login'],
        soni: j['soni'],
      );
}

class RekordKun {
  final String sana;
  final double jamiKg;

  RekordKun({required this.sana, required this.jamiKg});

  factory RekordKun.fromJson(Map<String, dynamic> j) =>
      RekordKun(sana: j['sana'], jamiKg: (j['jami_kg'] as num).toDouble());
}
