import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/statistika.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

class StatistikaEkrani extends StatefulWidget {
  const StatistikaEkrani({super.key});

  @override
  State<StatistikaEkrani> createState() => _StatistikaEkraniState();
}

class _StatistikaEkraniState extends State<StatistikaEkrani> {
  String _davr = 'kunlik';
  DavrJamlanmasi? _jamlanma;
  bool _yuklanmoqda = true;
  String? _xato;

  @override
  void initState() {
    super.initState();
    _yuklash();
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final javob = await context.read<AppState>().api.get('/statistika/jamlanma', query: {'davr': _davr});
      setState(() => _jamlanma = DavrJamlanmasi.fromJson(javob));
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
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
          if (!_yuklanmoqda && _xato == null && _jamlanma != null) Expanded(child: _tarkib(lok)),
        ],
      ),
    );
  }

  Widget _tarkib(dynamic lok) {
    final j = _jamlanma!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${j.boshlanishSanasi} — ${j.tugashSanasi}  |  ${lok.t("jami")}: ${j.jamiSoni} ${lok.t("soni")}, ${j.jamiKg.toStringAsFixed(1)} kg',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          if (j.mahsulotlar.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('—')))
          else ...[
            SizedBox(height: 260, child: _grafik(j.mahsulotlar)),
            const SizedBox(height: 24),
            ...j.mahsulotlar.map(
              (m) => Card(
                child: ListTile(
                  title: Text(m.mahsulotNomi),
                  trailing: Text('${m.soni} ${lok.t("soni")} — ${m.jamiKg.toStringAsFixed(1)} kg'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _grafik(List<MahsulotJamlanmasi> mahsulotlar) {
    final maxKg = mahsulotlar.map((m) => m.jamiKg).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxKg == 0 ? 10 : maxKg * 1.2,
        barGroups: [
          for (var i = 0; i < mahsulotlar.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: mahsulotlar[i].jamiKg, color: kipTaroziYashil, width: 28)]),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= mahsulotlar.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(mahsulotlar[i].mahsulotNomi));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
      ),
    );
  }
}
