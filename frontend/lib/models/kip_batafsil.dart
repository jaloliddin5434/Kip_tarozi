class AuditLogYozuvi {
  final int id;
  final int foydalanuvchiId;
  final String foydalanuvchiIsm;
  final String jadvalNomi;
  final int yozuvId;
  final String amal;
  final Map<String, dynamic>? eskiQiymat;
  final Map<String, dynamic>? yangiQiymat;
  final String sabab;
  final DateTime vaqt;

  AuditLogYozuvi({
    required this.id,
    required this.foydalanuvchiId,
    required this.foydalanuvchiIsm,
    required this.jadvalNomi,
    required this.yozuvId,
    required this.amal,
    this.eskiQiymat,
    this.yangiQiymat,
    required this.sabab,
    required this.vaqt,
  });

  factory AuditLogYozuvi.fromJson(Map<String, dynamic> j) => AuditLogYozuvi(
        id: j['id'],
        foydalanuvchiId: j['foydalanuvchi_id'],
        foydalanuvchiIsm: j['foydalanuvchi_ism'],
        jadvalNomi: j['jadval_nomi'],
        yozuvId: j['yozuv_id'],
        amal: j['amal'],
        eskiQiymat: j['eski_qiymat'] == null ? null : Map<String, dynamic>.from(j['eski_qiymat']),
        yangiQiymat: j['yangi_qiymat'] == null ? null : Map<String, dynamic>.from(j['yangi_qiymat']),
        sabab: j['sabab'],
        vaqt: DateTime.parse(j['vaqt']),
      );
}

class KipBatafsil {
  final int id;
  final String mijozId;
  final int partiyaId;
  final int partiyaRaqami;
  final String mahsulotKodi;
  final String mahsulotNomi;
  final int kipRaqami;
  final double ogirlik;
  final String smena;
  final int operatorId;
  final String operatorIsm;
  final DateTime mahalliyVaqt;
  final DateTime vaqt;
  final bool sinxronlangan;
  final String? suratYoli;
  final String holati;
  final int? stansiyaId;
  final List<AuditLogYozuvi> auditLog;

  KipBatafsil({
    required this.id,
    required this.mijozId,
    required this.partiyaId,
    required this.partiyaRaqami,
    required this.mahsulotKodi,
    required this.mahsulotNomi,
    required this.kipRaqami,
    required this.ogirlik,
    required this.smena,
    required this.operatorId,
    required this.operatorIsm,
    required this.mahalliyVaqt,
    required this.vaqt,
    required this.sinxronlangan,
    this.suratYoli,
    required this.holati,
    this.stansiyaId,
    required this.auditLog,
  });

  factory KipBatafsil.fromJson(Map<String, dynamic> j) => KipBatafsil(
        id: j['id'],
        mijozId: j['mijoz_id'],
        partiyaId: j['partiya_id'],
        partiyaRaqami: j['partiya_raqami'],
        mahsulotKodi: j['mahsulot_kodi'],
        mahsulotNomi: j['mahsulot_nomi'],
        kipRaqami: j['kip_raqami'],
        ogirlik: (j['ogirlik'] as num).toDouble(),
        smena: j['smena'],
        operatorId: j['operator_id'],
        operatorIsm: j['operator_ism'],
        mahalliyVaqt: DateTime.parse(j['mahalliy_vaqt']),
        vaqt: DateTime.parse(j['vaqt']),
        sinxronlangan: j['sinxronlangan'],
        suratYoli: j['surat_yoli'],
        holati: j['holati'],
        stansiyaId: j['stansiya_id'],
        auditLog: (j['audit_log'] as List).map((e) => AuditLogYozuvi.fromJson(e)).toList(),
      );
}
