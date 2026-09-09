import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/hujjat.dart';
import '../../models/kamera_tasdiq.dart';
import '../../state/app_state.dart';

/// "Kamera ishlamasa — Admin ruxsati" oqimining Admin tomoni.
/// Kutilayotgan so'rovlar ro'yxati + "Tasdiqlash" / "Rad etish".
/// Har 5 soniyada avtomatik yangilanadi (operator blokda kutayotgani uchun).
class KameraTasdiqlariEkrani extends StatefulWidget {
  const KameraTasdiqlariEkrani({super.key});

  @override
  State<KameraTasdiqlariEkrani> createState() => _KameraTasdiqlariEkraniState();
}

class _KameraTasdiqlariEkraniState extends State<KameraTasdiqlariEkrani> {
  static const int _sahifaHajmi = 30;

  Sahifalangan<KameraTasdiqSorovi>? _sahifa;
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
      final javob = await api.get('/kamera-tasdiq', query: query);
      if (!mounted) return;
      setState(() {
        _sahifa = Sahifalangan.fromJson(javob, (e) => KameraTasdiqSorovi.fromJson(e));
        _xato = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!jimgina) setState(() => _xato = e.toString());
    } finally {
      if (mounted && !jimgina) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _tasdiqlash(KameraTasdiqSorovi s) async {
    await _amal(() => context.read<AppState>().api.post('/kamera-tasdiq/${s.id}/tasdiqlash'));
  }

  Future<void> _radEtish(KameraTasdiqSorovi s) async {
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
            '/kamera-tasdiq/${s.id}/rad-etish',
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
              Text(lok.t('kamera_tasdiqlari'), style: Theme.of(context).textTheme.titleLarge),
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
      return Center(child: Text(lok.t('kamera_tasdiqlari_yoq')));
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
                  DataColumn(label: Text(lok.t('smena'))),
                  DataColumn(label: Text(lok.t('operator'))),
                  DataColumn(label: Text(lok.t('mahsulot'))),
                  DataColumn(label: Text(lok.t('partiya_raqami'))),
                  DataColumn(label: Text(lok.t('kg'))),
                  DataColumn(label: Text(lok.t('holati'))),
                  DataColumn(label: Text('')),
                ],
                rows: sahifa.items.map((s) => _qator(lok, s)).toList(),
              ),
            ),
          ),
        ),
        _sahifalash(lok, sahifa),
      ],
    );
  }

  DataRow _qator(dynamic lok, KameraTasdiqSorovi s) {
    return DataRow(cells: [
      DataCell(Text('${s.vaqt.toLocal()}'.substring(0, 16))),
      DataCell(Text(s.smena)),
      DataCell(Text(s.operatorIsm)),
      DataCell(Text(s.mahsulotNomi)),
      DataCell(Text('#${s.partiyaRaqami}')),
      DataCell(Text(s.ogirlik.toStringAsFixed(1))),
      DataCell(_holatChip(lok, s)),
      DataCell(
        s.kutilmoqda
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: _amalBajarilmoqda ? null : () => _tasdiqlash(s),
                    child: Text(lok.t('tasdiqlash')),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _amalBajarilmoqda ? null : () => _radEtish(s),
                    child: Text(lok.t('rad_etish')),
                  ),
                ],
              )
            : Text(
                [s.halQilganIsm, s.halQilishManbasi == 'telegram' ? 'Telegram' : null]
                    .where((e) => e != null)
                    .join(' · '),
                style: const TextStyle(color: Colors.grey),
              ),
      ),
    ]);
  }

  Widget _holatChip(dynamic lok, KameraTasdiqSorovi s) {
    final (matn, rang) = switch (s.holati) {
      'tasdiqlangan' => (lok.t('tasdiqlangan'), Colors.green.shade100),
      'rad_etilgan' => (lok.t('rad_etilgan'), Colors.red.shade100),
      _ => (lok.t('kutilmoqda'), Colors.orange.shade100),
    };
    return Chip(label: Text(matn), backgroundColor: rang);
  }

  Widget _sahifalash(dynamic lok, Sahifalangan<KameraTasdiqSorovi> sahifa) {
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
