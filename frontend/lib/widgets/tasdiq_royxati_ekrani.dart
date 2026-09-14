import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/hujjat.dart';
import '../models/tasdiq_yozuvi.dart';
import '../state/app_state.dart';

/// Admin "tasdiqlash/rad etish" navbati ko'rinishidagi ekranlar uchun umumiy
/// widget — kamera-tasdiq so'rovlari (`kamera_tasdiqlari_screen.dart`) va
/// kip-to'g'rilash zayavkalari (`kip_togrilash_screen.dart`) o'rtasidagi kod
/// takrorini yo'q qilish uchun chiqarilgan (AUDIT TUZATISHI — refaktoring,
/// xatti-harakat o'zgarmagan).
///
/// Ikkala ekran ham: kutilayotgan/hal-qilingan ro'yxat, sahifalash, har 5
/// soniyada avtomatik yangilanish, "Tasdiqlash"/"Rad etish" (izoh bilan)
/// amallari bo'yicha bir xil. Farq faqat: model turi (`T`), backend endpoint
/// prefiksi, sarlavha/bo'sh-ro'yxat matni, jadval ustunlari va model-ga xos
/// katakchalar (vaqt/operator kabi umumiylaridan tashqari) — bularning
/// barchasi shu widgetga parametr sifatida uzatiladi.
class TasdiqRoyxatiEkrani<T extends TasdiqYozuvi> extends StatefulWidget {
  /// Backend endpoint prefiksi, masalan `/kamera-tasdiq` yoki `/kip-togrilash`.
  /// Ro'yxat shu manzildan (`GET`) yuklanadi. Amallar (`tasdiqlash`/
  /// `rad-etish`) ham standart holda shu prefiksdan foydalanadi — qarang
  /// [amalEndpointi].
  final String endpointYoli;
  final T Function(Map<String, dynamic>) itemFromJson;

  /// Ixtiyoriy: har bir QATOR uchun amal (`tasdiqlash`/`rad-etish`) qaysi
  /// backend prefiksiga borishi kerakligini aniqlaydi. Berilmasa
  /// [endpointYoli] ishlatiladi (bitta turdagi ro'yxat ekranlari uchun
  /// standart xatti-harakat). Bir nechta ASL manbadan (masalan kamera-tasdiq
  /// + kip-to'g'irlash) birlashtirilgan ro'yxatda — bu yerda id'lar ikkala
  /// jadval bo'yicha MUSTAQIL (bir xil qiymat ikki xil yozuvga tegishli
  /// bo'lishi mumkin) — shuning uchun har bir qator o'zining haqiqiy
  /// manbasiga (masalan `item.tur`ga qarab) yo'naltirilishi SHART.
  final String Function(T item)? amalEndpointi;

  /// Sahifa sarlavhasi va "ro'yxat bo'sh" matnlari uchun i18n kalitlari.
  final String sarlavhaKaliti;
  final String royxatBoshKaliti;

  /// Jadval ustunlari (8 tasi — 6 tasi model-ga xos + "Holati" + amal ustuni).
  final List<DataColumn> Function(dynamic lok) ustunlarQurish;

  /// Bitta qator uchun model-ga xos katakchalar (umumiy "Holati" va amal
  /// katakchalaridan TASHQARI — ularni shu widget o'zi qo'shadi).
  final List<DataCell> Function(dynamic lok, T item) katakchalarQurish;

  /// Ixtiyoriy — qatorni ajratib ko'rsatish uchun fon rangi (masalan
  /// kamera-tasdiq ekranidagi dublikat-shubhasi ogohlantirishi). `null`
  /// qaytarilsa qator oddiy ko'rinadi.
  final Color? Function(T item)? qatorRangi;

  const TasdiqRoyxatiEkrani({
    super.key,
    required this.endpointYoli,
    required this.itemFromJson,
    required this.sarlavhaKaliti,
    required this.royxatBoshKaliti,
    required this.ustunlarQurish,
    required this.katakchalarQurish,
    this.qatorRangi,
    this.amalEndpointi,
  });

  @override
  State<TasdiqRoyxatiEkrani<T>> createState() => _TasdiqRoyxatiEkraniState<T>();
}

class _TasdiqRoyxatiEkraniState<T extends TasdiqYozuvi> extends State<TasdiqRoyxatiEkrani<T>> {
  static const int _sahifaHajmi = 30;

  Sahifalangan<T>? _sahifa;
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
      final javob = await api.get(widget.endpointYoli, query: query);
      if (!mounted) return;
      setState(() {
        _sahifa = Sahifalangan.fromJson(javob, widget.itemFromJson);
        _xato = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!jimgina) setState(() => _xato = e.toString());
    } finally {
      if (mounted && !jimgina) setState(() => _yuklanmoqda = false);
    }
  }

  String _amalUchunEndpoint(T item) => widget.amalEndpointi?.call(item) ?? widget.endpointYoli;

  Future<void> _tasdiqlash(T item) async {
    await _amal(() => context.read<AppState>().api.post('${_amalUchunEndpoint(item)}/${item.id}/tasdiqlash'));
  }

  Future<void> _radEtish(T item) async {
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
            '${_amalUchunEndpoint(item)}/${item.id}/rad-etish',
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
              Text(lok.t(widget.sarlavhaKaliti), style: Theme.of(context).textTheme.titleLarge),
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
      return Center(child: Text(lok.t(widget.royxatBoshKaliti)));
    }
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: widget.ustunlarQurish(lok),
                rows: sahifa.items.map((item) => _qator(lok, item)).toList(),
              ),
            ),
          ),
        ),
        _sahifalash(lok, sahifa),
      ],
    );
  }

  DataRow _qator(dynamic lok, T item) {
    final rang = widget.qatorRangi?.call(item);
    return DataRow(
      color: rang != null ? WidgetStateProperty.all(rang) : null,
      cells: [
        ...widget.katakchalarQurish(lok, item),
        DataCell(_holatChip(lok, item)),
        DataCell(
          item.kutilmoqda
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _amalBajarilmoqda ? null : () => _tasdiqlash(item),
                      child: Text(lok.t('tasdiqlash')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _amalBajarilmoqda ? null : () => _radEtish(item),
                      child: Text(lok.t('rad_etish')),
                    ),
                  ],
                )
              : Text(
                  [item.halQilganIsm, item.halQilishManbasi == 'telegram' ? 'Telegram' : null]
                      .where((e) => e != null)
                      .join(' · '),
                  style: const TextStyle(color: Colors.grey),
                ),
        ),
      ],
    );
  }

  Widget _holatChip(dynamic lok, T item) {
    final (matn, rang) = switch (item.holati) {
      'tasdiqlangan' => (lok.t('tasdiqlangan'), Colors.green.shade100),
      'rad_etilgan' => (lok.t('rad_etilgan'), Colors.red.shade100),
      _ => (lok.t('kutilmoqda'), Colors.orange.shade100),
    };
    return Chip(label: Text(matn), backgroundColor: rang);
  }

  Widget _sahifalash(dynamic lok, Sahifalangan<T> sahifa) {
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
