import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../models/moliyaviy.dart';
import '../../state/app_state.dart';

class MoliyaviyHisobotEkrani extends StatefulWidget {
  const MoliyaviyHisobotEkrani({super.key});

  @override
  State<MoliyaviyHisobotEkrani> createState() => _MoliyaviyHisobotEkraniState();
}

class _MoliyaviyHisobotEkraniState extends State<MoliyaviyHisobotEkrani> {
  String _davr = 'oylik';
  List<UzexNarx>? _narxlar;
  MoliyaviyHisobot? _hisobot;
  bool _yuklanmoqda = true;
  String? _xato;

  @override
  void initState() {
    super.initState();
    _yuklash();
  }

  void _xatoKorsat(String xabar) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(xabar), backgroundColor: Colors.red.shade700));
  }

  Future<void> _yuklash() async {
    final holat = context.read<AppState>();
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final natijalar = await Future.wait([
        holat.moliyaviyGet('/moliyaviy/uzex-narxlar'),
        holat.moliyaviyGet('/moliyaviy/hisobot', query: {'davr': _davr}),
      ]);
      if (!mounted) return;
      setState(() {
        _narxlar = (natijalar[0] as List).map((e) => UzexNarx.fromJson(e)).toList();
        _hisobot = MoliyaviyHisobot.fromJson(natijalar[1]);
      });
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _xatoKorsat(holat.lok.t('moliyaviy_sessiya_tugadi'));
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      setState(() => _xato = e.xabar);
    } catch (e) {
      if (!mounted) return;
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Scaffold(
      appBar: AppBar(title: Text(lok.t('moliyaviy'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_narxlar != null) ...[_uzexPaneli(lok), const SizedBox(height: 20)],
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'kunlik', label: Text(lok.t('davr_kunlik'))),
                ButtonSegment(value: 'haftalik', label: Text(lok.t('davr_haftalik'))),
                ButtonSegment(value: 'oylik', label: Text(lok.t('davr_oylik'))),
                ButtonSegment(value: 'mavsum', label: Text(lok.t('davr_mavsum'))),
              ],
              selected: {_davr},
              onSelectionChanged: (s) {
                setState(() => _davr = s.first);
                _yuklash();
              },
            ),
            const SizedBox(height: 20),
            if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
            if (!_yuklanmoqda && _xato == null && _hisobot != null) Expanded(child: _hisobotTarkibi(lok)),
          ],
        ),
      ),
    );
  }

  Widget _uzexPaneli(dynamic lok) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lok.t('uzex_narxlari'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _narxlar!
                  .map((n) => Chip(label: Text('${n.mahsulotNomi}: ${_somFormat(n.narxSom)} ${lok.t("som")}')))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hisobotTarkibi(dynamic lok) {
    final h = _hisobot!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${h.boshlanishSanasi} — ${h.tugashSanasi}  |  ${lok.t("jami")}: ${_somFormat(h.jamiSumma)} ${lok.t("som")}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (h.mahsulotlar.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('—')))
          else
            ...h.mahsulotlar.map(
              (m) => Card(
                child: ListTile(
                  title: Text(m.mahsulotNomi),
                  subtitle: Text('${m.partiyalarSoni} ${lok.t("soni")} · ${m.jamiSofVazn.toStringAsFixed(1)} kg'),
                  trailing: Text(
                    '${_somFormat(m.jamiSumma)} ${lok.t("som")}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _somFormat(double qiymat) {
    final butun = qiymat.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < butun.length; i++) {
      if (i > 0 && (butun.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(butun[i]);
    }
    return buffer.toString();
  }
}
