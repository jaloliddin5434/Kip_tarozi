import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/hujjat.dart';
import '../../models/kip_togrilash.dart';
import '../../state/app_state.dart';

/// "Kip to'g'rilash so'rovi" oqimining Admin tomoni — kamera_tasdiqlari_screen
/// bilan bir xil uslub: kutilayotgan zayavkalar ro'yxati + "Tasdiqlash" /
/// "Rad etish". Har 5 soniyada avtomatik yangilanadi.
class KipTogrilashEkrani extends StatefulWidget {
  const KipTogrilashEkrani({super.key});

  @override
  State<KipTogrilashEkrani> createState() => _KipTogrilashEkraniState();
}

class _KipTogrilashEkraniState extends State<KipTogrilashEkrani> {
  static const int _sahifaHajmi = 30;

  Sahifalangan<KipTogrilashZayavkasi>? _sahifa;
  bool _yuklanmoqda = true;
  bool _amalBajarilmoqda = false;
  String? _xato;
  bool _faqatKutilayotgan = true;
  int _joriySahifa = 1;
  Timer? _avtoYangilash;

  @override
  void initState() {
    super.initState();
    _yuklash();
    _avtoYangilash = Timer.periodic(const Duration(seconds: 5), (_) => _yuklash(jimgina: true));
  }

  @override
  void dispose() {
    _avtoYangilash?.cancel();
    super.dispose();
  }

  Future<void> _yuklash({bool jimgina = false}) async {
    if (!jimgina) setState(() => _yuklanmoqda = true);
    try {
      final api = context.read<AppState>().api;
      final query = <String, dynamic>{'sahifa': _joriySahifa, 'sahifa_hajmi': _sahifaHajmi};
      if (_faqatKutilayotgan) query['holati'] = 'kutilmoqda';
      final javob = await api.get('/kip-togrilash', query: query);
      if (!mounted) return;
      setState(() {
        _sahifa = Sahifalangan.fromJson(javob, (e) => KipTogrilashZayavkasi.fromJson(e));
        _xato = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!jimgina) setState(() => _xato = e.toString());
    } finally {
      if (mounted && !jimgina) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _tasdiqlash(KipTogrilashZayavkasi z) async {
    await _amal(() => context.read<AppState>().api.post('/kip-togrilash/${z.id}/tasdiqlash'));
  }

  Future<void> _radEtish(KipTogrilashZayavkasi z) async {
    final lok = context.read<AppState>().lok;
    final kontroller = TextEditingController();
    final tasdiq = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(lok.t('rad_etish')),
        content: TextField(
          controller: kontroller,
          decoration: InputDecoration(labelText: lok.t('rad_etish_sababi')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(lok.t('bekor_qilish'))),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(lok.t('rad_etish'))),
        ],
      ),
    );
    if (tasdiq != true) return;
    await _amal(
      () => context.read<AppState>().api.post(
            '/kip-togrilash/${z.id}/rad-etish',
            tana: {'izoh': kontroller.text.trim().isEmpty ? null : kontroller.text.trim()},
          ),
    );
  }

  Future<void> _amal(Future<void> Function() ish) async {
    setState(() => _amalBajarilmoqda = true);
    try {
      await ish();
      await _yuklash(jimgina: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _amalBajarilmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(lok.t('kip_togrilash_sorovlari'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 16),
              FilterChip(
                label: Text(lok.t('kutilmoqda')),
                selected: _faqatKutilayotgan,
                onSelected: (v) {
                  setState(() {
                    _faqatKutilayotgan = v;
                    _joriySahifa = 1;
                  });
                  _yuklash();
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _yuklash(),
                tooltip: lok.t('tozalash'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null) Expanded(child: _jadval(lok)),
        ],
      ),
    );
  }

  Widget _jadval(dynamic lok) {
    final sahifa = _sahifa!;
    if (sahifa.items.isEmpty) {
      return Center(child: Text(lok.t('kip_togrilash_sorovlari_yoq')));
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text(lok.t('vaqt'))),
                  DataColumn(label: Text(lok.t('operator'))),
                  DataColumn(label: Text(lok.t('kip_raqami'))),
                  DataColumn(label: Text('${lok.t('eski_mahsulot')} (${lok.t('mahsulot')})')),
                  DataColumn(label: Text('${lok.t('yangi_mahsulot')} (${lok.t('mahsulot')})')),
                  DataColumn(label: Text(lok.t('sabab'))),
                  DataColumn(label: Text(lok.t('holati'))),
                  DataColumn(label: Text('')),
                ],
                rows: sahifa.items.map((z) => _qator(lok, z)).toList(),
              ),
            ),
          ),
        ),
        _sahifalash(lok, sahifa),
      ],
    );
  }

  DataRow _qator(dynamic lok, KipTogrilashZayavkasi z) {
    return DataRow(cells: [
      DataCell(Text('${z.vaqt.toLocal()}'.substring(0, 16))),
      DataCell(Text(z.operatorIsm)),
      DataCell(Text('№${z.kipRaqami}')),
      DataCell(Text('${z.eskiMahsulotNomi} #${z.eskiPartiyaRaqami}')),
      DataCell(Text('${z.yangiMahsulotNomi} #${z.yangiPartiyaRaqami}')),
      DataCell(SizedBox(width: 160, child: Text(z.sabab, overflow: TextOverflow.ellipsis, maxLines: 2))),
      DataCell(_holatChip(lok, z)),
      DataCell(
        z.kutilmoqda
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: _amalBajarilmoqda ? null : () => _tasdiqlash(z),
                    child: Text(lok.t('tasdiqlash')),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _amalBajarilmoqda ? null : () => _radEtish(z),
                    child: Text(lok.t('rad_etish')),
                  ),
                ],
              )
            : Text(
                [z.halQilganIsm, z.halQilishManbasi == 'telegram' ? 'Telegram' : null]
                    .where((e) => e != null)
                    .join(' · '),
                style: const TextStyle(color: Colors.grey),
              ),
      ),
    ]);
  }

  Widget _holatChip(dynamic lok, KipTogrilashZayavkasi z) {
    final (matn, rang) = switch (z.holati) {
      'tasdiqlangan' => (lok.t('tasdiqlangan'), Colors.green.shade100),
      'rad_etilgan' => (lok.t('rad_etilgan'), Colors.red.shade100),
      _ => (lok.t('kutilmoqda'), Colors.orange.shade100),
    };
    return Chip(label: Text(matn), backgroundColor: rang);
  }

  Widget _sahifalash(dynamic lok, Sahifalangan<KipTogrilashZayavkasi> sahifa) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _joriySahifa > 1
              ? () {
                  setState(() => _joriySahifa--);
                  _yuklash();
                }
              : null,
        ),
        Text('${sahifa.sahifa}  (${lok.t("jami")}: ${sahifa.jami})'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: sahifa.sahifa * sahifa.sahifaHajmi < sahifa.jami
              ? () {
                  setState(() => _joriySahifa++);
                  _yuklash();
                }
              : null,
        ),
      ],
    );
  }
}
