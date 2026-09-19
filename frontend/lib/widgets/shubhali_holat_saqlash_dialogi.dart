import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_exception.dart';
import '../models/mahsulot.dart';
import '../models/partiya.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Admin "Shubhali holatlar" ro'yxatidagi bir "yuk saqlanmadi" hodisasini
/// HAQIQIY Kip sifatida saqlash uchun mahsulot/partiya tanlaydigan dialog —
/// `kip_togrilash_dialogi.dart` bilan bir xil naqsh (mahsulot tugmalari +
/// ochiq partiyalar chipi + qo'lda kiritish), faqat "sabab" maydonisiz
/// (hodisaning o'zi sabab — operator tomonidan yaratilmagan).
/// Muvaffaqiyatli bo'lsa `true` bilan yopiladi (chaqiruvchi snackbar
/// ko'rsatadi), aks holda `false`/`null`.
Future<bool?> shubhaliHolatSaqlashDialogniKorsat({
  required BuildContext context,
  required AppState holat,
  required List<Mahsulot> mahsulotlar,
  required int hodisaId,
  required double ogirlik,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ShubhaliHolatSaqlashDialogi(
      holat: holat,
      mahsulotlar: mahsulotlar,
      hodisaId: hodisaId,
      ogirlik: ogirlik,
    ),
  );
}

class _ShubhaliHolatSaqlashDialogi extends StatefulWidget {
  final AppState holat;
  final List<Mahsulot> mahsulotlar;
  final int hodisaId;
  final double ogirlik;

  const _ShubhaliHolatSaqlashDialogi({
    required this.holat,
    required this.mahsulotlar,
    required this.hodisaId,
    required this.ogirlik,
  });

  @override
  State<_ShubhaliHolatSaqlashDialogi> createState() => _ShubhaliHolatSaqlashDialogiState();
}

class _ShubhaliHolatSaqlashDialogiState extends State<_ShubhaliHolatSaqlashDialogi> {
  final _partiyaKontrolleri = TextEditingController();
  Mahsulot? _tanlanganMahsulot;
  bool _yuborilmoqda = false;
  String? _xato;

  // kip_togrilash_dialogi.dart bilan bir xil naqsh — qarang o'sha faylning
  // izohlari (chip "faol" holati partiya-raqami matnidan hisoblanadi,
  // ro'yxatda yo'q partiya raqamini ham qo'lda kiritish mumkin).
  List<Partiya> _ochiqPartiyalar = [];
  bool _partiyalarYuklanmoqda = false;

  @override
  void initState() {
    super.initState();
    _partiyaKontrolleri.addListener(_partiyaMatniOzgardi);
  }

  void _partiyaMatniOzgardi() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _partiyaKontrolleri.removeListener(_partiyaMatniOzgardi);
    _partiyaKontrolleri.dispose();
    super.dispose();
  }

  Future<void> _mahsulotTanlash(Mahsulot mahsulot) async {
    setState(() {
      _tanlanganMahsulot = mahsulot;
      _partiyaKontrolleri.clear();
      _ochiqPartiyalar = [];
      _partiyalarYuklanmoqda = true;
    });
    try {
      final javob = await widget.holat.api.get('/partiyalar/ochiq', query: {'mahsulot_kodi': mahsulot.kod});
      if (_tanlanganMahsulot?.id != mahsulot.id || !mounted) return;
      setState(() => _ochiqPartiyalar = (javob as List).map((e) => Partiya.fromJson(e)).toList());
    } catch (_) {
      // Ro'yxat yuklanmasa ham dialog ishlayveradi — admin partiya
      // raqamini qo'lda kirita oladi.
    } finally {
      if (mounted && _tanlanganMahsulot?.id == mahsulot.id) {
        setState(() => _partiyalarYuklanmoqda = false);
      }
    }
  }

  void _partiyaniTanlash(Partiya partiya) {
    setState(() => _partiyaKontrolleri.text = partiya.partiyaRaqami.toString());
  }

  Future<void> _yuborish() async {
    final lok = widget.holat.lok;
    final mahsulot = _tanlanganMahsulot;
    final partiyaRaqami = int.tryParse(_partiyaKontrolleri.text.trim());

    if (mahsulot == null || partiyaRaqami == null || partiyaRaqami < 1) {
      setState(() => _xato = lok.t('shubhali_holat_malumotlar_notogri'));
      return;
    }

    setState(() {
      _yuborilmoqda = true;
      _xato = null;
    });
    try {
      await widget.holat.api.post(
        '/shubhali-holatlar/${widget.hodisaId}/saqlash',
        tana: {'mahsulot_kodi': mahsulot.kod, 'partiya_raqami': partiyaRaqami},
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _xato = e.xabar);
    } catch (e) {
      if (mounted) setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuborilmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lok = widget.holat.lok;
    return AlertDialog(
      title: Text(lok.t('shubhali_holat_saqlash_sarlavha')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${lok.t('kg')}: ${widget.ogirlik.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(lok.t('shubhali_holat_mahsulot_tanlang'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.mahsulotlar.map((m) => _mahsulotTugmasi(m)).toList(),
              ),
              const SizedBox(height: 16),
              if (_partiyalarYuklanmoqda)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (!_partiyalarYuklanmoqda && _ochiqPartiyalar.isNotEmpty) ...[
                Text(lok.t('ochiq_partiyalar'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ochiqPartiyalar
                      .map(
                        (p) => _partiyaChipi(
                          matn: '#${p.partiyaRaqami} (${p.kipSoni})',
                          faol: _partiyaKontrolleri.text == p.partiyaRaqami.toString(),
                          onTap: () => _partiyaniTanlash(p),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _partiyaKontrolleri,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: lok.t('partiya_raqami'), border: const OutlineInputBorder()),
              ),
              if (_xato != null) ...[
                const SizedBox(height: 8),
                Text(_xato!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _yuborilmoqda ? null : () => Navigator.of(context).pop(false),
          child: Text(lok.t('bekor_qilish')),
        ),
        FilledButton(
          onPressed: _yuborilmoqda ? null : _yuborish,
          child: _yuborilmoqda
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(lok.t('saqlash')),
        ),
      ],
    );
  }

  Widget _mahsulotTugmasi(Mahsulot m) {
    final rang = mahsulotRangi(m.kod);
    final tanlanganmi = _tanlanganMahsulot?.id == m.id;
    return Material(
      color: tanlanganmi ? rang : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _mahsulotTanlash(m),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: rang, width: tanlanganmi ? 0 : 1.4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            m.nomi,
            style: TextStyle(fontWeight: FontWeight.bold, color: tanlanganmi ? Colors.white : rang),
          ),
        ),
      ),
    );
  }

  Widget _partiyaChipi({required String matn, required bool faol, required VoidCallback onTap}) {
    return ActionChip(
      label: Text(
        matn,
        style: TextStyle(color: faol ? Colors.white : Colors.black87, fontWeight: faol ? FontWeight.bold : FontWeight.normal),
      ),
      backgroundColor: faol ? kipTaroziYashil : Colors.grey.shade200,
      side: BorderSide(color: faol ? kipTaroziYashil : Colors.grey.shade300),
      onPressed: onTap,
    );
  }
}
