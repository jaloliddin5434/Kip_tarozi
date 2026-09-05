import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard.dart';
import '../../models/hujjat.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

/// Kanonik mahsulot kodlari va smena harflari — davrga ma'lumoti yo'q
/// mahsulot/smena bo'lsa ham UI'da har doim to'liq 4 tadan ko'rsatiladi
/// (0 qiymat bilan), aks holda "faqat ma'lumoti bor narsa ko'rinadi" degan
/// chalg'ituvchi taassurot qoladi.
const _mahsulotKodlari = ['tola', 'lint', 'pux', 'ulyuk'];
const _smenaHarflari = ['A', 'B', 'C', 'D'];

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
  List<HujjatKip>? _songgiHodisalar;

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
    final api = context.read<AppState>().api;
    try {
      final javob = await api.get('/dashboard', query: {'davr': _davr});
      setState(() => _dashboard = Dashboard.fromJson(javob));
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }

    try {
      final hodisaJavob = await api.get('/hujjatlar/kiplar', query: {'sahifa': 1, 'sahifa_hajmi': 6});
      if (mounted) {
        setState(() {
          _songgiHodisalar = (hodisaJavob['items'] as List).map((e) => HujjatKip.fromJson(e)).toList();
        });
      }
    } catch (_) {
      // Jimgina o'tkazib yuboriladi — bu qo'shimcha/ixtiyoriy panel,
      // asosiy dashboard ma'lumotini bloklamasligi kerak.
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
            _jamiKartasi(lok.t('jami'), '${d.jamiSoni} ${lok.t("soni")}\n${d.jamiKg.toStringAsFixed(1)} ${lok.t("kg")}'),
            _statKartasi(
              sarlavha: lok.t('ochiq_partiyalar'),
              qiymat: '${d.ochiqPartiyalarSoni}',
              ikonka: Icons.folder_open,
              rang: mahsulotRanglari['lint']!,
            ),
            _statKartasi(
              sarlavha: lok.t('shubhali_holatlar'),
              qiymat: '${d.tasdiqlanmaganShubhaliHolatlarSoni}',
              ikonka: Icons.warning_amber_rounded,
              rang: mahsulotRanglari['pux']!,
            ),
            _agentKartasi(
              lok.t('agent_holati'),
              d.agentHolati != null && d.agentHolati!.yangimi ? lok.t('ulangan') : lok.t('ulanmagan'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(lok.t('mahsulot'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _mahsulotGridi(lok, d),
        const SizedBox(height: 28),
        Text(lok.t('smena_boyicha'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(height: 240, child: _smenaGrafigi(d.smenalar)),
        const SizedBox(height: 28),
        Text(lok.t('songgi_hodisalar'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _songgiHodisalarPaneli(lok),
        const SizedBox(height: 16),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Davr xulosasi kartalari
  // ---------------------------------------------------------------------

  Widget _jamiKartasi(String sarlavha, String qiymat) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F6E56), Color(0xFF1D9E75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: kipTaroziYashil.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.scale, size: 30, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sarlavha, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: 2),
                Text(qiymat, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statKartasi({required String sarlavha, required String qiymat, required IconData ikonka, required Color rang}) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: rang.withValues(alpha: 0.06),
        border: Border.all(color: rang.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: rang.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(ikonka, size: 30, color: rang),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sarlavha, style: TextStyle(fontSize: 12, color: rang.withValues(alpha: 0.85))),
                const SizedBox(height: 2),
                Text(qiymat, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: rang)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Stansiya agenti kartasi — "Ulanmagan" hozircha xato emas, kutilgan
  /// holat (real qurilma hali ulanmagan), shuning uchun boshqa kartalardan
  /// farqli, HAR DOIM neytral kulrang — real ulanish holatidan qat'iy nazar.
  Widget _agentKartasi(String sarlavha, String qiymat) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Icon(Icons.sensors, size: 30, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sarlavha, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        qiymat,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mahsulot — operator ekranidagi kabi rangli 2x2 grid
  // ---------------------------------------------------------------------

  Widget _mahsulotGridi(dynamic lok, Dashboard d) {
    final xarita = {for (final m in d.mahsulotlar) m.mahsulotKodi: m};

    Widget katak(String kod) {
      final m = xarita[kod];
      final rang = mahsulotRangi(kod);
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: rang.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: rang, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lok.t(kod), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: rang)),
              const SizedBox(height: 6),
              Text('${m?.soni ?? 0}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: rang)),
              const SizedBox(height: 2),
              Text('${(m?.jamiKg ?? 0).toStringAsFixed(1)} ${lok.t("kg")}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [katak(_mahsulotKodlari[0]), katak(_mahsulotKodlari[1])]),
        const SizedBox(height: 8),
        Row(children: [katak(_mahsulotKodlari[2]), katak(_mahsulotKodlari[3])]),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Smena bo'yicha grafigi
  // ---------------------------------------------------------------------

  /// Y o'q uchun "toza" interval — 4 ta chiziqqa bo'linadi, har doim
  /// 1/2/5 (yoki ularning 10 karralilari) qatoridan tanlanadi, shu bilan
  /// fl_chart'ning avtomatik intervalidan farqli, yorliqlar hech qachon
  /// bir-birining ustiga tushmasligi KAFOLATLANADI (aniq belgilangan
  /// interval — kutubxonaning ehtimoliy noaniq avto-hisoblashiga tayanmaydi).
  double _yoqOraligi(double qiymat) {
    if (qiymat <= 0) return 1;
    final daraja = (math.log(qiymat) / math.ln10).floor();
    final asos = qiymat / math.pow(10, daraja);
    double kopaytuvchi;
    if (asos <= 1) {
      kopaytuvchi = 1;
    } else if (asos <= 2) {
      kopaytuvchi = 2;
    } else if (asos <= 5) {
      kopaytuvchi = 5;
    } else {
      kopaytuvchi = 10;
    }
    return kopaytuvchi * math.pow(10, daraja).toDouble();
  }

  String _sonFormat(double qiymat) {
    if (qiymat >= 1000) {
      var matn = (qiymat / 1000).toStringAsFixed(1);
      if (matn.endsWith('.0')) matn = matn.substring(0, matn.length - 2);
      return '${matn}K';
    }
    return qiymat.round().toString();
  }

  /// HAR DOIM 4 ta ustun (A/B/C/D) chizadi — ma'lumoti yo'q smena uchun
  /// ham ingichka kulrang ustun (0 qiymat bilan), "faqat ma'lumoti bor
  /// smenalar ko'rinadi" degan avvalgi xatoni tuzatadi. Har bir ustun
  /// ustida uning aniq qiymati doimiy yorliq sifatida ko'rsatiladi.
  Widget _smenaGrafigi(List<SmenaJamlanmasi> xom) {
    final xarita = {for (final s in xom) s.smena: s};
    final tugallangan = [
      for (final harf in _smenaHarflari) xarita[harf] ?? SmenaJamlanmasi(smena: harf, soni: 0, jamiKg: 0),
    ];

    final maxKg = tugallangan.map((s) => s.jamiKg).fold<double>(0, (a, b) => a > b ? a : b);
    final xomMaxY = maxKg == 0 ? 10.0 : maxKg * 1.3;
    final interval = _yoqOraligi(xomMaxY / 4);
    final maxY = interval * 4;

    return BarChart(
      BarChartData(
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 6,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              rod.toY.round().toString(),
              TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < tugallangan.length; i++)
            BarChartGroupData(
              x: i,
              showingTooltipIndicators: const [0],
              barRods: [
                BarChartRodData(
                  toY: tugallangan[i].jamiKg,
                  color: tugallangan[i].soni > 0 ? kipTaroziYashil : Colors.grey.shade300,
                  width: tugallangan[i].soni > 0 ? 28 : 10,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: interval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(_sonFormat(value), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= tugallangan.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Text(tugallangan[i].smena, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // So'nggi hodisalar — /hujjatlar/kiplar'dan oxirgi bir nechta yozuv
  // ---------------------------------------------------------------------

  String _vaqtQisqa(DateTime v) {
    final l = v.toLocal();
    String ikki(int s) => s.toString().padLeft(2, '0');
    return '${ikki(l.day)}.${ikki(l.month)} ${ikki(l.hour)}:${ikki(l.minute)}';
  }

  Widget _songgiHodisalarPaneli(dynamic lok) {
    final royxat = _songgiHodisalar;
    if (royxat == null || royxat.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Center(child: Text(lok.t('malumot_yoq'), style: TextStyle(color: Colors.grey.shade500))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          for (var i = 0; i < royxat.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
            _hodisaQatori(lok, royxat[i]),
          ],
        ],
      ),
    );
  }

  Widget _hodisaQatori(dynamic lok, HujjatKip h) {
    final rang = mahsulotRangi(h.mahsulotKodi);
    final bekorMi = h.holati != 'aktiv';
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: rang.withValues(alpha: 0.12),
        child: Icon(Icons.scale, size: 16, color: rang),
      ),
      title: Text(
        '${h.mahsulotNomi} #${h.kipRaqami} — ${h.ogirlik.toStringAsFixed(1)} ${lok.t("kg")}',
        style: TextStyle(
          decoration: bekorMi ? TextDecoration.lineThrough : null,
          color: bekorMi ? Colors.grey : null,
        ),
      ),
      subtitle: Text('${h.operatorIsm} • ${lok.t("smena")} ${h.smena}'),
      trailing: Text(_vaqtQisqa(h.vaqt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
}
