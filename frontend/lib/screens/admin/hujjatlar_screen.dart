import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../models/hujjat.dart';
import '../../services/fayl_yuklab_olish.dart';
import '../../services/hujjat_pdf.dart';
import '../../state/app_state.dart';
import '../../widgets/kalendar_vidjeti.dart';
import '../../widgets/kip_batafsil_dialog.dart';

class HujjatlarEkrani extends StatefulWidget {
  const HujjatlarEkrani({super.key});

  @override
  State<HujjatlarEkrani> createState() => _HujjatlarEkraniState();
}

class _HujjatlarEkraniState extends State<HujjatlarEkrani> {
  Sahifalangan<HujjatKip>? _sahifa;
  bool _yuklanmoqda = true;
  String? _xato;
  int _joriySahifa = 1;

  final _mahsulotKontrolleri = TextEditingController();
  final _kipRaqamiKontrolleri = TextEditingController();
  final _qidiruvKontrolleri = TextEditingController();
  Timer? _qidiruvTaymer;
  String? _smenaFiltri;
  String? _holatiFiltri;
  DateTime? _sanaDan;
  DateTime? _sanaGacha;

  @override
  void initState() {
    super.initState();
    // Ekran ochilganda standart holatda "bugun" (kunlik) filtr qo'llaniladi.
    final bugun = DateTime.now();
    _sanaDan = bugun;
    _sanaGacha = bugun;
    _yuklash();
  }

  @override
  void dispose() {
    _qidiruvTaymer?.cancel();
    _qidiruvKontrolleri.dispose();
    super.dispose();
  }

  void _qidiruvOzgardi(String qiymat) {
    _qidiruvTaymer?.cancel();
    _qidiruvTaymer = Timer(const Duration(milliseconds: 500), () {
      _joriySahifa = 1;
      _yuklash();
    });
  }

  bool get _bugunTanlanganmi {
    bool birXilKunmi(DateTime? d) {
      final bugun = DateTime.now();
      return d != null && d.year == bugun.year && d.month == bugun.month && d.day == bugun.day;
    }

    return birXilKunmi(_sanaDan) && birXilKunmi(_sanaGacha);
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final query = <String, dynamic>{'sahifa': _joriySahifa, 'sahifa_hajmi': 30};
      if (_mahsulotKontrolleri.text.trim().isNotEmpty) query['mahsulot_kodi'] = _mahsulotKontrolleri.text.trim();
      if (_kipRaqamiKontrolleri.text.trim().isNotEmpty) query['kip_raqami'] = int.tryParse(_kipRaqamiKontrolleri.text.trim());
      if (_qidiruvKontrolleri.text.trim().isNotEmpty) query['qidiruv'] = _qidiruvKontrolleri.text.trim();
      if (_smenaFiltri != null) query['smena'] = _smenaFiltri;
      if (_holatiFiltri != null) query['holati'] = _holatiFiltri;
      if (_sanaDan != null) query['sana_dan'] = _sanaDan!.toIso8601String().substring(0, 10);
      if (_sanaGacha != null) query['sana_gacha'] = _sanaGacha!.toIso8601String().substring(0, 10);

      final javob = await context.read<AppState>().api.get('/hujjatlar/kiplar', query: query);
      setState(() => _sahifa = Sahifalangan.fromJson(javob, (e) => HujjatKip.fromJson(e)));
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _chopEtish(HujjatKip kip, dynamic lok) async {
    final hujjat = kipHujjatiQur(kip, lok);
    await Printing.layoutPdf(onLayout: (format) async => hujjat.save());
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

  void _bugunTanlash() {
    final bugun = DateTime.now();
    setState(() {
      _sanaDan = bugun;
      _sanaGacha = bugun;
      _joriySahifa = 1;
    });
    _yuklash();
  }

  /// Kalendarda faqat "sana_dan" va "sana_gacha" bitta xil kunga o'rnatilgan
  /// bo'lsagina tegishli kun belgilanadi — aks holda (diapazon yoki filtr
  /// tozalangan) kalendarda hech qanday kun tanlangan ko'rinmaydi.
  DateTime? get _kalendarTanlanganKun {
    final dan = _sanaDan;
    final gacha = _sanaGacha;
    if (dan == null || gacha == null) return null;
    if (dan.year == gacha.year && dan.month == gacha.month && dan.day == gacha.day) return dan;
    return null;
  }

  void _kalendarKunTanlash(DateTime kun) {
    setState(() {
      _sanaDan = kun;
      _sanaGacha = kun;
      _joriySahifa = 1;
    });
    _yuklash();
  }

  Future<void> _excelHisobotDialogniOchish() async {
    final holat = context.read<AppState>();
    final lok = holat.lok;
    var tanlanganSana = DateTime.now();
    var tanlanganSmena = 'A';
    var yuklanmoqda = false;
    String? xato;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> yuklab() async {
            setDialogState(() {
              yuklanmoqda = true;
              xato = null;
            });
            try {
              final sana = tanlanganSana.toIso8601String().substring(0, 10);
              final baytlar = await holat.api.getBaytlar(
                '/hisobotlar/smena-excel',
                query: {'sana': sana, 'smena': tanlanganSmena},
              );
              faylniSaqlash(baytlar, 'Smena_${tanlanganSmena}_$sana.xlsx');
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lok.t('fayl_yuklab_olindi'))));
              }
            } on ApiException catch (e) {
              setDialogState(() => xato = e.xabar);
            } catch (e) {
              setDialogState(() => xato = e.toString());
            } finally {
              setDialogState(() => yuklanmoqda = false);
            }
          }

          return AlertDialog(
            title: Text(lok.t('excel_hisobot_tanlash')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(tanlanganSana.toIso8601String().substring(0, 10)),
                  onPressed: () async {
                    final tanlangan = await showDatePicker(
                      context: dialogContext,
                      initialDate: tanlanganSana,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (tanlangan != null) setDialogState(() => tanlanganSana = tanlangan);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tanlanganSmena,
                  decoration: InputDecoration(labelText: lok.t('smena'), border: const OutlineInputBorder()),
                  items: ['A', 'B', 'C', 'D'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => tanlanganSmena = v);
                  },
                ),
                if (xato != null) ...[
                  const SizedBox(height: 12),
                  Text(xato!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(lok.t('bekor'))),
              FilledButton.icon(
                onPressed: yuklanmoqda ? null : yuklab,
                icon: yuklanmoqda
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download, size: 18),
                label: Text(lok.t('yuklab_olish')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _filtrniTozalash() {
    _mahsulotKontrolleri.clear();
    _kipRaqamiKontrolleri.clear();
    _qidiruvKontrolleri.clear();
    _smenaFiltri = null;
    _holatiFiltri = null;
    _sanaDan = null;
    _sanaGacha = null;
    _joriySahifa = 1;
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _qidiruvKontrolleri,
                  onChanged: _qidiruvOzgardi,
                  decoration: InputDecoration(
                    labelText: lok.t('qidiruv'),
                    hintText: lok.t('qidiruv_maslahat'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _mahsulotKontrolleri,
                  decoration: InputDecoration(labelText: lok.t('mahsulot'), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _kipRaqamiKontrolleri,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: lok.t('kip_qisqa'), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _smenaFiltri,
                  decoration: InputDecoration(labelText: lok.t('smena'), border: const OutlineInputBorder(), isDense: true),
                  items: ['A', 'B', 'C', 'D'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _smenaFiltri = v),
                ),
              ),
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
              ChoiceChip(
                label: Text(lok.t('bugun')),
                selected: _bugunTanlanganmi,
                onSelected: (_) => _bugunTanlash(),
              ),
              ChoiceChip(
                label: Text(lok.t('faqat_tahrirlangan')),
                selected: _holatiFiltri == 'tahrirlangan',
                selectedColor: Colors.orange.withValues(alpha: 0.25),
                onSelected: (tanlandi) {
                  setState(() {
                    _holatiFiltri = tanlandi ? 'tahrirlangan' : null;
                    _joriySahifa = 1;
                  });
                  _yuklash();
                },
              ),
              ChoiceChip(
                label: Text(lok.t('faqat_bekor_qilingan')),
                selected: _holatiFiltri == 'bekor_qilingan',
                selectedColor: Colors.red.withValues(alpha: 0.20),
                onSelected: (tanlandi) {
                  setState(() {
                    _holatiFiltri = tanlandi ? 'bekor_qilingan' : null;
                    _joriySahifa = 1;
                  });
                  _yuklash();
                },
              ),
              ElevatedButton(onPressed: () { _joriySahifa = 1; _yuklash(); }, child: Text(lok.t('filtr'))),
              OutlinedButton(onPressed: _filtrniTozalash, child: Text(lok.t('tozalash'))),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: Text(lok.t('excel_yuklab_olish')),
                onPressed: _excelHisobotDialogniOchish,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 340,
            child: KalendarVidjeti(tanlanganKun: _kalendarTanlanganKun, onKunTanlash: _kalendarKunTanlash),
          ),
          const SizedBox(height: 16),
          if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null) Expanded(child: _jadval(lok)),
        ],
      ),
    );
  }

  Color? _qatorRangi(String holati) {
    switch (holati) {
      case 'bekor_qilingan':
        return Colors.red.withValues(alpha: 0.08);
      case 'tahrirlangan':
        return Colors.orange.withValues(alpha: 0.10);
      default:
        return null;
    }
  }

  Color _holatiMatnRangi(String holati) {
    switch (holati) {
      case 'bekor_qilingan':
        return Colors.red.shade700;
      case 'tahrirlangan':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  // Ustun kengliklari — sarlavha va ma'lumot qatorlari bir xil tekislanishi
  // uchun ikkalasida ham xuddi shu kengliklar ishlatiladi.
  static const _ustunKengliklari = <double>[150, 90, 80, 60, 70, 90, 160, 140, 100];

  Widget _jadval(dynamic lok) {
    final sahifa = _sahifa!;
    final jadvalKengligi = _ustunKengliklari.fold<double>(0, (a, b) => a + b);
    final ustunNomlari = [
      lok.t('sana'),
      lok.t('mahsulot'),
      lok.t('partiya'),
      lok.t('kip_qisqa'),
      lok.t('kg'),
      lok.t('smena'),
      lok.t('operator'),
      lok.t('holati'),
      lok.t('chop_etish'),
    ];

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: jadvalKengligi,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sarlavha qatori — vertikal aylantirishdan tashqarida, doim ko'rinib turadi.
                  Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < ustunNomlari.length; i++)
                          SizedBox(
                            width: _ustunKengliklari[i],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Text(ustunNomlari[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: sahifa.items.map((k) => _malumotQatori(k, lok)).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _joriySahifa > 1 ? () { setState(() => _joriySahifa--); _yuklash(); } : null,
            ),
            Text('${sahifa.sahifa} / ${(sahifa.jami / sahifa.sahifaHajmi).ceil().clamp(1, 999999)}  (${lok.t("jami")}: ${sahifa.jami})'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: sahifa.sahifa * sahifa.sahifaHajmi < sahifa.jami ? () { setState(() => _joriySahifa++); _yuklash(); } : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _malumotQatori(HujjatKip k, dynamic lok) {
    return InkWell(
      onTap: () => kipBatafsilDialogniKorsat(context: context, kipId: k.id),
      child: Container(
        color: _qatorRangi(k.holati),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            _hujayra(0, Text('${k.vaqt.toLocal()}'.substring(0, 16))),
            _hujayra(1, Text(k.mahsulotNomi, overflow: TextOverflow.ellipsis)),
            _hujayra(2, Text('#${k.partiyaRaqami}')),
            _hujayra(3, Text('${k.kipRaqami}')),
            _hujayra(4, Text(k.ogirlik.toStringAsFixed(1))),
            _hujayra(5, Text(k.smena)),
            _hujayra(6, Text(k.operatorIsm, overflow: TextOverflow.ellipsis)),
            _hujayra(
              7,
              Text(
                k.holati,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _holatiMatnRangi(k.holati), fontWeight: FontWeight.w600),
              ),
            ),
            _hujayra(
              8,
              IconButton(
                icon: const Icon(Icons.print, size: 20),
                tooltip: lok.t('chop_etish'),
                onPressed: () => _chopEtish(k, lok),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hujayra(int ustunIndex, Widget bola) {
    return SizedBox(
      width: _ustunKengliklari[ustunIndex],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(alignment: Alignment.centerLeft, child: bola),
      ),
    );
  }
}
