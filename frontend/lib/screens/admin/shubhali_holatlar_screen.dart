import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/hujjat.dart';
import '../../models/shubhali_holat.dart';
import '../../state/app_state.dart';

class ShubhaliHolatlarEkrani extends StatefulWidget {
  const ShubhaliHolatlarEkrani({super.key});

  @override
  State<ShubhaliHolatlarEkrani> createState() => _ShubhaliHolatlarEkraniState();
}

class _ShubhaliHolatlarEkraniState extends State<ShubhaliHolatlarEkrani> {
  static const int _sahifaHajmi = 20;

  Sahifalangan<ShubhaliHolat>? _sahifa;
  ShubhaliHolatStatistika? _statistika;
  bool _yuklanmoqda = true;
  String? _xato;
  String? _smenaFiltri;
  DateTime? _sanaDan;
  DateTime? _sanaGacha;
  int _joriySahifa = 1;

  @override
  void initState() {
    super.initState();
    _yuklash();
  }

  Map<String, dynamic> _filtrQuery() {
    final query = <String, dynamic>{};
    if (_smenaFiltri != null) query['smena'] = _smenaFiltri;
    if (_sanaDan != null) query['sana_dan'] = _sanaDan!.toIso8601String().substring(0, 10);
    if (_sanaGacha != null) query['sana_gacha'] = _sanaGacha!.toIso8601String().substring(0, 10);
    return query;
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final api = context.read<AppState>().api;
      final royxatQuery = {..._filtrQuery(), 'sahifa': _joriySahifa, 'sahifa_hajmi': _sahifaHajmi};
      final natijalar = await Future.wait([
        api.get('/shubhali-holatlar', query: royxatQuery),
        api.get('/shubhali-holatlar/statistika', query: _filtrQuery()),
      ]);
      setState(() {
        _sahifa = Sahifalangan.fromJson(natijalar[0], (e) => ShubhaliHolat.fromJson(e));
        _statistika = ShubhaliHolatStatistika.fromJson(natijalar[1]);
      });
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _sanaTanlash({required bool boshlanish}) async {
    final tanlangan = await showDatePicker(
      context: context,
      initialDate: (boshlanish ? _sanaDan : _sanaGacha) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (tanlangan == null) return;
    setState(() {
      if (boshlanish) {
        _sanaDan = tanlangan;
      } else {
        _sanaGacha = tanlangan;
      }
      _joriySahifa = 1;
    });
    _yuklash();
  }

  void _filtrniTozalash() {
    setState(() {
      _smenaFiltri = null;
      _sanaDan = null;
      _sanaGacha = null;
      _joriySahifa = 1;
    });
    _yuklash();
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statistika != null) ...[
            Text(lok.t('smena_boyicha'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: ['A', 'B', 'C', 'D'].map((s) => _statKartasi(s, '${_statistika!.smenaBoyicha[s] ?? 0}')).toList(),
            ),
            const SizedBox(height: 20),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...['A', 'B', 'C', 'D'].map(
                (s) => ChoiceChip(
                  label: Text(s),
                  selected: _smenaFiltri == s,
                  onSelected: (_) {
                    setState(() {
                      _smenaFiltri = _smenaFiltri == s ? null : s;
                      _joriySahifa = 1;
                    });
                    _yuklash();
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_sanaDan == null ? lok.t('sana_dan') : _sanaDan!.toIso8601String().substring(0, 10)),
                onPressed: () => _sanaTanlash(boshlanish: true),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_sanaGacha == null ? lok.t('sana_gacha') : _sanaGacha!.toIso8601String().substring(0, 10)),
                onPressed: () => _sanaTanlash(boshlanish: false),
              ),
              ActionChip(label: Text(lok.t('tozalash')), onPressed: _filtrniTozalash),
            ],
          ),
          const SizedBox(height: 16),
          if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null) Expanded(child: _jadval(lok)),
        ],
      ),
    );
  }

  Widget _statKartasi(String smena, String qiymat) {
    return SizedBox(
      width: 140,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(smena, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              Text(qiymat, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jadval(dynamic lok) {
    final sahifa = _sahifa!;
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
                  DataColumn(label: Text(lok.t('kg'))),
                  DataColumn(label: Text(lok.t('holati'))),
                ],
                rows: sahifa.items
                    .map(
                      (h) => DataRow(cells: [
                        DataCell(Text('${h.vaqt.toLocal()}'.substring(0, 16))),
                        DataCell(Text(h.smena ?? '—')),
                        DataCell(Text(h.operatorIsm ?? '—')),
                        DataCell(Text(h.ogirlik.toStringAsFixed(1))),
                        DataCell(
                          Chip(
                            label: Text(h.tasdiqlangan ? lok.t('korib_chiqildi') : lok.t('yangi')),
                            backgroundColor: h.tasdiqlangan ? Colors.green.shade100 : Colors.red.shade100,
                          ),
                        ),
                      ]),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        Row(
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
            Text(
              '${sahifa.sahifa} / ${(sahifa.jami / sahifa.sahifaHajmi).ceil().clamp(1, 999999)}  (${lok.t("jami")}: ${sahifa.jami})',
            ),
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
        ),
      ],
    );
  }
}
