import 'tasdiq_yozuvi.dart';

/// `GET /tasdiqlash-tarixi` javobi — kamera-tasdiq so'rovlari va
/// kip-to'g'rilash zayavkalarini BITTA normallashtirilgan qatorga
/// birlashtirgan yozuv. `tur` ('kamera' | 'kip_togrilash') qaysi asl
/// jadvaldan kelganini bildiradi; shu maydon orqali [amalEndpointi] ham
/// tegishli backend endpointini (tasdiqlash/rad-etish uchun) tanlaydi —
/// shunda IKKITA turli model o'rniga bitta model bilan
/// `TasdiqRoyxatiEkrani<TasdiqTarixiYozuvi>`ni ishlatish mumkin.
class TasdiqTarixiYozuvi implements TasdiqYozuvi {
  @override
  final int id;
  final String tur;
  final DateTime vaqt;
  final String operatorIsm;
  final String tavsif;
  final String? sabab;
  @override
  final String holati; // kutilmoqda | tasdiqlangan | rad_etilgan
  final DateTime? halQilinganVaqt;
  @override
  final String? halQilganIsm;
  @override
  final String? halQilishManbasi;
  final String? izoh;
  final bool dublikatShubhasi;

  TasdiqTarixiYozuvi({
    required this.id,
    required this.tur,
    required this.vaqt,
    required this.operatorIsm,
    required this.tavsif,
    this.sabab,
    required this.holati,
    this.halQilinganVaqt,
    this.halQilganIsm,
    this.halQilishManbasi,
    this.izoh,
    this.dublikatShubhasi = false,
  });

  @override
  bool get kutilmoqda => holati == 'kutilmoqda';

  bool get kameraTuri => tur == 'kamera';

  String get amalEndpointi => kameraTuri ? '/kamera-tasdiq' : '/kip-togrilash';

  factory TasdiqTarixiYozuvi.fromJson(Map<String, dynamic> j) => TasdiqTarixiYozuvi(
        id: j['id'],
        tur: j['tur'],
        vaqt: DateTime.parse(j['vaqt']),
        operatorIsm: j['operator_ism'],
        tavsif: j['tavsif'],
        sabab: j['sabab'],
        holati: j['holati'],
        halQilinganVaqt: j['hal_qilingan_vaqt'] == null ? null : DateTime.parse(j['hal_qilingan_vaqt']),
        halQilganIsm: j['hal_qilgan_ism'],
        halQilishManbasi: j['hal_qilish_manbasi'],
        izoh: j['izoh'],
        dublikatShubhasi: j['dublikat_shubhasi'] == true,
      );
}
