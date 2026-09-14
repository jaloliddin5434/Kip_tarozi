import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/hujjat.dart';
import '../../models/tasdiqlash_tarixi.dart';
import '../../state/app_state.dart';
import '../../widgets/kalendar_vidjeti.dart';
import '../../widgets/tasdiq_royxati_ekrani.dart';

/// "Kamera tasdiqlari" va "Kip to'g'irlash so'rovlari" ekranlarini
/// birlashtirgan admin ekrani (AUDIT/UX yaxshilash — ikkita alohida menyu
/// bandi o'rniga bitta, "turi" ustuni bilan farqlanadigan umumiy ro'yxat).
///
/// Yuqorida — umumiy `TasdiqRoyxatiEkrani<TasdiqTarixiYozuvi>` (backend:
/// `GET /tasdiqlash-tarixi`, ikkala manbani `tur` maydoni bilan
/// birlashtiradi). O'ng tomonda — `KalendarVidjeti` (Statistika/Hujjatlar
/// bilan bir xil): bir kunga bosilganda O'SHA KUNDA hal qilingan
/// (tasdiqlangan/rad etilgan) BARCHA yozuvlar (ikkala turi ham) alohida
/// tafsilot panelida ko'rsatiladi.
class TasdiqlashTarixiEkrani extends StatefulWidget {
  const TasdiqlashTarixiEkrani({super.key});

  @override
  State<TasdiqlashTarixiEkrani> createState() => _TasdiqlashTarixiEkraniState();
}

class _TasdiqlashTarixiEkraniState extends State<TasdiqlashTarixiEkrani> {
  DateTime? _tanlanganKun;
  List<TasdiqTarixiYozuvi>? _kunYozuvlari;
  bool _kunYuklanmoqda = false;
  String? _kunXato;

  Future<void> _kunTanlash(DateTime kun) async {
    setState(() {
      _tanlanganKun = kun;
      _kunYuklanmoqda = true;
      _kunXato = null;
    });
    try {
      final api = context.read<AppState>().api;
      final javob = await api.get(
        '/tasdiqlash-tarixi',
        query: {'hal_qilingan_sana': _sanaFormat(kun), 'sahifa_hajmi': 500},
      );
      if (!mounted) return;
      setState(() {
        _kunYozuvlari = Sahifalangan.fromJson(javob, TasdiqTarixiYozuvi.fromJson).items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _kunXato = e.toString());
    } finally {
      if (mounted) setState(() => _kunYuklanmoqda = false);
    }
  }

  String _sanaFormat(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TasdiqRoyxatiEkrani<TasdiqTarixiYozuvi>(
            endpointYoli: '/tasdiqlash-tarixi',
            itemFromJson: TasdiqTarixiYozuvi.fromJson,
            amalEndpointi: (item) => item.amalEndpointi,
            sarlavhaKaliti: 'tasdiqlash_tarixi',
            royxatBoshKaliti: 'tasdiqlash_tarixi_yoq',
            ustunlarQurish: (lok) => [
              DataColumn(label: Text(lok.t('turi'))),
              DataColumn(label: Text(lok.t('vaqt'))),
              DataColumn(label: Text(lok.t('operator'))),
              DataColumn(label: Text(lok.t('tavsif'))),
              DataColumn(label: Text(lok.t('sabab'))),
              DataColumn(label: Text(lok.t('holati'))),
              DataColumn(label: Text('')),
            ],
            katakchalarQurish: (lok, item) => [
              DataCell(_turiBelgisi(lok, item)),
              DataCell(Text('${item.vaqt.toLocal()}'.substring(0, 16))),
              DataCell(Text(item.operatorIsm)),
              DataCell(_tavsifXujayrasi(lok, item)),
              DataCell(
                SizedBox(
                  width: 160,
                  child: Text(item.sabab ?? '—', overflow: TextOverflow.ellipsis, maxLines: 2),
                ),
              ),
            ],
            // AUDIT TUZATISHI (kamera-tasdiq ekranidan ko'chirilgan): shu
            // partiyada yaqinda o'xshash og'irlik topilgan bo'lsa — butun
            // qatorni yengil sariq fon bilan ajratib ko'rsatamiz (faqat
            // DIQQATni tortish uchun, hech narsa avtomatik bloklanmaydi).
            qatorRangi: (item) => item.dublikatShubhasi ? Colors.amber.withValues(alpha: 0.12) : null,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KalendarVidjeti(tanlanganKun: _tanlanganKun, onKunTanlash: _kunTanlash),
                const SizedBox(height: 12),
                Expanded(child: _kunTafsiloti(lok)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  /// "Tavsif" katakchasi — kamera turidagi qatorda dublikat-shubhasi bo'lsa,
  /// yoniga sariq ogohlantirish belgisi (tooltip bilan) qo'shiladi. FAQAT
  /// vizual — admin baribir tasdiqlashi yoki rad etishi mumkin.
  Widget _tavsifXujayrasi(dynamic lok, TasdiqTarixiYozuvi item) {
    final matn = SizedBox(
      width: 200,
      child: Text(item.tavsif, overflow: TextOverflow.ellipsis, maxLines: 2),
    );
    if (!item.dublikatShubhasi) return matn;
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

  Widget _turiBelgisi(dynamic lok, TasdiqTarixiYozuvi item) {
    return Chip(
      avatar: Icon(item.kameraTuri ? Icons.photo_camera_front_outlined : Icons.edit_note, size: 16),
      label: Text(lok.t(item.kameraTuri ? 'kamera' : 'togrilash')),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _kunTafsiloti(dynamic lok) {
    if (_tanlanganKun == null) {
      return Center(child: Text(lok.t('kun_tanlang'), textAlign: TextAlign.center));
    }
    if (_kunYuklanmoqda) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_kunXato != null) {
      return Center(child: Text(_kunXato!));
    }
    final yozuvlar = _kunYozuvlari ?? const <TasdiqTarixiYozuvi>[];
    if (yozuvlar.isEmpty) {
      return Center(child: Text(lok.t('kun_uchun_sorov_yoq'), textAlign: TextAlign.center));
    }
    return ListView.separated(
      itemCount: yozuvlar.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _yozuvKartasi(lok, yozuvlar[i]),
    );
  }

  Widget _yozuvKartasi(dynamic lok, TasdiqTarixiYozuvi y) {
    final tasdiqlanganmi = y.holati == 'tasdiqlangan';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _turiBelgisi(lok, y),
                Chip(
                  label: Text(lok.t(tasdiqlanganmi ? 'tasdiqlangan' : 'rad_etilgan')),
                  backgroundColor: tasdiqlanganmi ? Colors.green.shade100 : Colors.red.shade100,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(y.tavsif, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${lok.t('operator')}: ${y.operatorIsm}'),
            if (y.sabab != null && y.sabab!.isNotEmpty) Text('${lok.t('sabab')}: ${y.sabab}'),
            if (y.halQilganIsm != null)
              Text(
                '${lok.t('hal_qildi')}: ${y.halQilganIsm}'
                '${y.halQilishManbasi == 'telegram' ? ' · Telegram' : ''}',
              ),
            if (y.izoh != null && y.izoh!.isNotEmpty) Text('${lok.t('izoh')}: ${y.izoh}'),
          ],
        ),
      ),
    );
  }
}
