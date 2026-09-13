import 'package:flutter/material.dart';
import '../../models/kamera_tasdiq.dart';
import '../../widgets/tasdiq_royxati_ekrani.dart';

/// "Kamera ishlamasa — Admin ruxsati" oqimining Admin tomoni.
/// Kutilayotgan so'rovlar ro'yxati + "Tasdiqlash" / "Rad etish".
/// Umumiy tuzilma (sahifalash, avto-yangilanish, amallar) endi
/// `widgets/tasdiq_royxati_ekrani.dart`da (`kip_togrilash_screen.dart` bilan
/// bir xil) — bu yerda faqat model/endpoint/matnlarga xos qismlar qoladi.
class KameraTasdiqlariEkrani extends StatelessWidget {
  const KameraTasdiqlariEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return TasdiqRoyxatiEkrani<KameraTasdiqSorovi>(
      endpointYoli: '/kamera-tasdiq',
      itemFromJson: KameraTasdiqSorovi.fromJson,
      sarlavhaKaliti: 'kamera_tasdiqlari',
      royxatBoshKaliti: 'kamera_tasdiqlari_yoq',
      ustunlarQurish: (lok) => [
        DataColumn(label: Text(lok.t('vaqt'))),
        DataColumn(label: Text(lok.t('smena'))),
        DataColumn(label: Text(lok.t('operator'))),
        DataColumn(label: Text(lok.t('mahsulot'))),
        DataColumn(label: Text(lok.t('partiya_raqami'))),
        DataColumn(label: Text(lok.t('kg'))),
        DataColumn(label: Text(lok.t('holati'))),
        DataColumn(label: Text('')),
      ],
      katakchalarQurish: (lok, s) => [
        DataCell(Text('${s.vaqt.toLocal()}'.substring(0, 16))),
        DataCell(Text(s.smena)),
        DataCell(Text(s.operatorIsm)),
        DataCell(Text(s.mahsulotNomi)),
        DataCell(Text('#${s.partiyaRaqami}')),
        DataCell(_ogirlikXujayrasi(lok, s)),
      ],
      // AUDIT TUZATISHI: shu partiyada yaqinda o'xshash og'irlik topilgan
      // bo'lsa — butun qatorni yengil sariq fon bilan ajratib ko'rsatamiz
      // (faqat DIQQATni tortish uchun, hech narsa avtomatik bloklanmaydi —
      // admin baribir tasdiqlashi yoki rad etishi mumkin).
      qatorRangi: (s) => s.dublikatShubhasi ? Colors.amber.withValues(alpha: 0.12) : null,
    );
  }

  /// Og'irlik matni — dublikat shubhasi bo'lsa yoniga sariq ogohlantirish
  /// belgisi (tooltip bilan) qo'shiladi. FAQAT vizual — admin baribir
  /// tasdiqlashi yoki rad etishi mumkin, hech narsa avtomatik bloklanmaydi.
  static Widget _ogirlikXujayrasi(dynamic lok, KameraTasdiqSorovi s) {
    final matn = Text(s.ogirlik.toStringAsFixed(1));
    if (!s.dublikatShubhasi) return matn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        matn,
        const SizedBox(width: 6),
        Tooltip(
          message: lok.t('dublikat_shubhasi_tooltip'),
          child: const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
        ),
      ],
    );
  }
}
