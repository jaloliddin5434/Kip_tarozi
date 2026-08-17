import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard.dart';
import '../../state/app_state.dart';

class DashboardEkrani extends StatefulWidget {
  const DashboardEkrani({super.key});

  @override
  State<DashboardEkrani> createState() => _DashboardEkraniState();
}

class _DashboardEkraniState extends State<DashboardEkrani> {
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
      final javob = await context.read<AppState>().api.get('/dashboard');
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

    if (_yuklanmoqda) return const Center(child: CircularProgressIndicator());
    if (_xato != null) return Center(child: Text(_xato!));
    final d = _dashboard!;

    return RefreshIndicator(
      onRefresh: _yuklash,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${lok.t("bugungi_statistika")} — ${d.sana}', style: Theme.of(context).textTheme.titleLarge),
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
          ...d.mahsulotlar.map(
            (m) => Card(
              child: ListTile(
                title: Text(m.mahsulotNomi),
                trailing: Text('${m.soni} ${lok.t("soni")} — ${m.jamiKg.toStringAsFixed(1)} kg'),
              ),
            ),
          ),
        ],
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
