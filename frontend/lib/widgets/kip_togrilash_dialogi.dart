import 'package:flutter/material.dart';
import '../api/api_exception.dart';
import '../models/mahsulot.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Operator "Smena tarixi" ro'yxatidagi bir kip uchun to'g'ri mahsulot/partiya
/// tanlab, admin tasdiqlashi uchun zayavka yuboradigan kichik dialog.
/// Muvaffaqiyatli yuborilsa `true` bilan yopiladi (chaqiruvchi snackbar
/// ko'rsatadi), aks holda `false`/`null`.
Future<bool?> kipTogrilashDialogniKorsat({
  required BuildContext context,
  required AppState holat,
  required List<Mahsulot> mahsulotlar,
  required int kipId,
  required int kipRaqami,
  required double ogirlik,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _KipTogrilashDialogi(
      holat: holat,
      mahsulotlar: mahsulotlar,
      kipId: kipId,
      kipRaqami: kipRaqami,
      ogirlik: ogirlik,
    ),
  );
}

class _KipTogrilashDialogi extends StatefulWidget {
  final AppState holat;
  final List<Mahsulot> mahsulotlar;
  final int kipId;
  final int kipRaqami;
  final double ogirlik;

  const _KipTogrilashDialogi({
    required this.holat,
    required this.mahsulotlar,
    required this.kipId,
    required this.kipRaqami,
    required this.ogirlik,
  });

  @override
  State<_KipTogrilashDialogi> createState() => _KipTogrilashDialogiState();
}

class _KipTogrilashDialogiState extends State<_KipTogrilashDialogi> {
  final _partiyaKontrolleri = TextEditingController();
  final _sababKontrolleri = TextEditingController();
  Mahsulot? _tanlanganMahsulot;
  bool _yuborilmoqda = false;
  String? _xato;

  @override
  void dispose() {
    _partiyaKontrolleri.dispose();
    _sababKontrolleri.dispose();
    super.dispose();
  }

  Future<void> _yuborish() async {
    final lok = widget.holat.lok;
    final mahsulot = _tanlanganMahsulot;
    final partiyaRaqami = int.tryParse(_partiyaKontrolleri.text.trim());
    final sabab = _sababKontrolleri.text.trim();

    if (mahsulot == null || partiyaRaqami == null || partiyaRaqami < 1 || sabab.isEmpty) {
      setState(() => _xato = lok.t('malumotlar_notogri'));
      return;
    }

    setState(() {
      _yuborilmoqda = true;
      _xato = null;
    });
    try {
      await widget.holat.api.post(
        '/kip-togrilash',
        tana: {
          'kip_id': widget.kipId,
          'yangi_mahsulot_kodi': mahsulot.kod,
          'yangi_partiya_raqami': partiyaRaqami,
          'sabab': sabab,
        },
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
      title: Text('${lok.t('kip_togrilash_dialog_sarlavha')} — №${widget.kipRaqami}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lok.t('kip_togrilash_yangi_mahsulot'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.mahsulotlar.map((m) => _mahsulotTugmasi(m)).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _partiyaKontrolleri,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: lok.t('partiya_raqami'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sababKontrolleri,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: lok.t('kip_togrilash_sabab_belgisi'), border: const OutlineInputBorder()),
            ),
            if (_xato != null) ...[
              const SizedBox(height: 8),
              Text(_xato!, style: const TextStyle(color: Colors.red)),
            ],
          ],
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
              : Text(lok.t('kip_togrilash_yuborish')),
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
        onTap: () => setState(() => _tanlanganMahsulot = m),
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
}
