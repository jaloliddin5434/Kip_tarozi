import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

class DashboardEkrani extends StatefulWidget {
  const DashboardEkrani({super.key});

  @override
  State<DashboardEkrani> createState() => _DashboardEkraniState();
}

class _DashboardEkraniState extends State<DashboardEkrani> {
  String _davr = 'kunlik';
  Dashboard? _dashboard;
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
      final javob = await context.read<AppState>().api.get('/dashboard', query: {'davr': _davr});
      setState(() => _dashboard = Dashboard.fromJson(javob));
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return RefreshIndicator(
      onRefresh: _yuklash,
      child: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          if (_yuklanmoqda) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _dashboard != null) _tarkib(lok),
        ],
      ),
    );
  }

  Widget _tarkib(dynamic lok) {
    final d = _dashboard!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${lok.t("davr_statistikasi")} — ${d.boshlanishSanasi} — ${d.tugashSanasi}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _statKartasi(lok.t('jami'), '${d.jamiSoni} ${lok.t("soni")}\n${d.jamiKg.toStringAsFixed(1)} kg', Icons.inventory_2),
            _statKartasi(lok.t('ochiq_partiyalar'), '${d.ochiqPartiyalarSoni}', Icons.folder_open),
            _statKartasi(
              lok.t('shubhali_holatlar'),
              '${d.tasdiqlanmaganShubhaliHolatlarSoni}',
              Icons.warning_amber,
              rangli: d.tasdiqlanmaganShubhaliHolatlarSoni > 0,
            ),
            _statKartasi(
              lok.t('agent_holati'),
              d.agentHolati != null && d.agentHolati!.yangimi ? lok.t('ulangan') : lok.t('ulanmagan'),
              Icons.sensors,
              rangli: d.agentHolati == null || !d.agentHolati!.yangimi,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(lok.t('mahsulot'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (d.mahsulotlar.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('—'))
        else
          ...d.mahsulotlar.map(
            (m) => Card(
              child: ListTile(
                title: Text(m.mahsulotNomi),
                trailing: Text('${m.soni} ${lok.t("soni")} — ${m.jamiKg.toStringAsFixed(1)} kg'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(lok.t('smena_boyicha'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (d.smenalar.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('—'))
        else
          SizedBox(height: 220, child: _smenaGrafigi(d.smenalar)),
      ],
    );
  }

  Widget _smenaGrafigi(List<SmenaJamlanmasi> smenalar) {
    final maxKg = smenalar.map((s) => s.jamiKg).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        maxY: maxKg == 0 ? 10 : maxKg * 1.2,
        barGroups: [
          for (var i = 0; i < smenalar.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: smenalar[i].jamiKg, color: kipTaroziYashil, width: 28)]),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= smenalar.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(smenalar[i].smena));
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

  Widget _statKartasi(String sarlavha, String qiymat, IconData ikonka, {bool rangli = false}) {
    return SizedBox(
      width: 220,
      child: Card(
        color: rangli ? Colors.red.withValues(alpha: 0.08) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(ikonka, size: 32, color: rangli ? Colors.red : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sarlavha, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(qiymat, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
