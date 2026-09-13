import 'package:flutter/material.dart';
import '../../models/kip_togrilash.dart';
import '../../widgets/tasdiq_royxati_ekrani.dart';

/// "Kip to'g'rilash so'rovi" oqimining Admin tomoni — kutilayotgan
/// zayavkalar ro'yxati + "Tasdiqlash" / "Rad etish". Umumiy tuzilma
/// (sahifalash, avto-yangilanish, amallar) endi
/// `widgets/tasdiq_royxati_ekrani.dart`da (`kamera_tasdiqlari_screen.dart`
/// bilan bir xil) — bu yerda faqat model/endpoint/matnlarga xos qismlar qoladi.
class KipTogrilashEkrani extends StatelessWidget {
  const KipTogrilashEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return TasdiqRoyxatiEkrani<KipTogrilashZayavkasi>(
      endpointYoli: '/kip-togrilash',
      itemFromJson: KipTogrilashZayavkasi.fromJson,
      sarlavhaKaliti: 'kip_togrilash_sorovlari',
      royxatBoshKaliti: 'kip_togrilash_sorovlari_yoq',
      ustunlarQurish: (lok) => [
        DataColumn(label: Text(lok.t('vaqt'))),
        DataColumn(label: Text(lok.t('operator'))),
        DataColumn(label: Text(lok.t('kip_raqami'))),
        DataColumn(label: Text('${lok.t('eski_mahsulot')} (${lok.t('mahsulot')})')),
        DataColumn(label: Text('${lok.t('yangi_mahsulot')} (${lok.t('mahsulot')})')),
        DataColumn(label: Text(lok.t('sabab'))),
        DataColumn(label: Text(lok.t('holati'))),
        DataColumn(label: Text('')),
      ],
      katakchalarQurish: (lok, z) => [
        DataCell(Text('${z.vaqt.toLocal()}'.substring(0, 16))),
        DataCell(Text(z.operatorIsm)),
        DataCell(Text('№${z.kipRaqami}')),
        DataCell(Text('${z.eskiMahsulotNomi} #${z.eskiPartiyaRaqami}')),
        DataCell(Text('${z.yangiMahsulotNomi} #${z.yangiPartiyaRaqami}')),
        DataCell(SizedBox(width: 160, child: Text(z.sabab, overflow: TextOverflow.ellipsis, maxLines: 2))),
      ],
    );
  }
}
