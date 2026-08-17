import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../i18n/strings.dart';
import '../../models/dashboard.dart';
import '../../models/statistika.dart';
import '../../services/statistika_pdf.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

const _mahsulotKodlari = ['tola', 'lint', 'pux', 'ulyuk'];

class StatistikaEkrani extends StatefulWidget {
  const StatistikaEkrani({super.key});

  @override
  State<StatistikaEkrani> createState() => _StatistikaEkraniState();
}

class _StatistikaEkraniState extends State<StatistikaEkrani> {
  String _davr = 'kunlik';
  String _mahsulot = 'tola';
  String? _smena; // null = "Jami" (barcha smenalar birlashtirilgan)

  DavrJamlanmasi? _jamlanma;
  List<SmenaJamlanmasi> _smenalar = [];
  bool _yuklanmoqda = true;
  String? _xato;

  DateTime _kalendarOy = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _tanlanganKun;
  DavrJamlanmasi? _kunlikJamlanma;
  bool _kunYuklanmoqda = false;
  String? _kunXato;

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
      final api = context.read<AppState>().api;

      final jamlanmaQuery = <String, dynamic>{'davr': _davr};
      if (_smena != null) jamlanmaQuery['smena'] = _smena;
      final jJavob = await api.get('/statistika/jamlanma', query: jamlanmaQuery);
      final jamlanma = DavrJamlanmasi.fromJson(jJavob);

      var smenalar = <SmenaJamlanmasi>[];
      if (_smena == null) {
        final sJavob = await api.get(
          '/statistika/smena-boyicha',
          query: {'davr': _davr, 'mahsulot_kodi': _mahsulot},
        );
        smenalar = (sJavob as List).map((e) => SmenaJamlanmasi.fromJson(e)).toList();
      }

      setState(() {
        _jamlanma = jamlanma;
        _smenalar = smenalar;
      });
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _kunTanlash(DateTime kun) async {
    setState(() {
      _tanlanganKun = kun;
      _kunYuklanmoqda = true;
      _kunXato = null;
    });
    try {
      final api = context.read<AppState>().api;
      final javob = await api.get('/statistika/jamlanma', query: {'davr': 'kunlik', 'sana': _sanaFormat(kun)});
      setState(() => _kunlikJamlanma = DavrJamlanmasi.fromJson(javob));
    } catch (e) {
      setState(() => _kunXato = e.toString());
    } finally {
      if (mounted) setState(() => _kunYuklanmoqda = false);
    }
  }

  String _sanaFormat(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _birXilKunmi(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  MahsulotJamlanmasi? get _tanlanganMahsulot {
    final j = _jamlanma;
    if (j == null) return null;
    for (final m in j.mahsulotlar) {
      if (m.mahsulotKodi == _mahsulot) return m;
    }
    return null;
  }

  Future<void> _eksportQil(Lokalizatsiya lok) async {
    final j = _jamlanma;
    if (j == null) return;
    final tanlangan = _tanlanganMahsulot;
    final soni = tanlangan?.soni ?? 0;
    final kg = tanlangan?.jamiKg ?? 0.0;
    final ortacha = soni == 0 ? 0.0 : kg / soni;

    final doc = statistikaHujjatiQur(
      jamlanma: j,
      mahsulotNomi: tanlangan?.mahsulotNomi ?? lok.t(_mahsulot),
      smena: _smena,
      smenalar: _smenalar,
      soni: soni,
      jamiKg: kg,
      ortachaOgirlik: ortacha,
      lok: lok,
    );
    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filtrQatori<String>(
            qiymatlar: const ['kunlik', 'haftalik', 'oylik', 'mavsum'],
            tanlangan: _davr,
            matn: (v) => lok.t('davr_$v'),
            onTanlash: (v) {
              setState(() => _davr = v);
              _yuklash();
            },
          ),
          const SizedBox(height: 10),
          _filtrQatori<String>(
            qiymatlar: _mahsulotKodlari,
            tanlangan: _mahsulot,
            matn: (v) => lok.t(v),
            onTanlash: (v) {
              setState(() => _mahsulot = v);
              _yuklash();
            },
          ),
          const SizedBox(height: 10),
          _filtrQatori<String?>(
            qiymatlar: const ['A', 'B', 'C', 'D', null],
            tanlangan: _smena,
            matn: (v) => v ?? lok.t('jami'),
            onTanlash: (v) {
              setState(() => _smena = v);
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

  Widget _filtrQatori<T>({
    required List<T> qiymatlar,
    required T tanlangan,
    required String Function(T) matn,
    required void Function(T) onTanlash,
  }) {
    return Row(
      children: [
        for (final v in qiymatlar)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _tugma(matn(v), v == tanlangan, () => onTanlash(v)),
            ),
          ),
      ],
    );
  }

  Widget _tugma(String matn, bool tanlanganmi, VoidCallback onTanlash) {
    return SizedBox(
      height: 44,
      child: tanlanganmi
          ? ElevatedButton(
              onPressed: onTanlash,
              style: ElevatedButton.styleFrom(backgroundColor: kipTaroziYashil, foregroundColor: Colors.white),
              child: Text(matn, overflow: TextOverflow.ellipsis),
            )
          : OutlinedButton(
              onPressed: onTanlash,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: kipTaroziYashil)),
              child: Text(matn, overflow: TextOverflow.ellipsis),
            ),
    );
  }

  Widget _tarkib(Lokalizatsiya lok) {
    final j = _jamlanma!;
    final tanlangan = _tanlanganMahsulot;
    final soni = tanlangan?.soni ?? 0;
    final kg = tanlangan?.jamiKg ?? 0.0;
    final ortacha = soni == 0 ? 0.0 : kg / soni;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${j.boshlanishSanasi} — ${j.tugashSanasi}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(lok.t('pdf_eksport')),
                onPressed: () => _eksportQil(lok),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _statKartasi(lok.t('jami'), '$soni ${lok.t("soni")}', Icons.inventory_2),
              _statKartasi('${lok.t("jami")} (kg)', '${kg.toStringAsFixed(1)} kg', Icons.scale),
              _statKartasi(lok.t('ortacha_ogirlik'), '${ortacha.toStringAsFixed(1)} kg', Icons.balance),
            ],
          ),
          const SizedBox(height: 24),
          if (_smena == null) ...[
            Text(lok.t('smenalar_taqqoslash'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_smenalar.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(lok.t('malumot_yoq')))
            else
              SizedBox(height: 240, child: _smenaGrafigi(_smenalar)),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(lok.t('kunlar_boyicha'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final kalendar = _kalendarVidjeti(lok);
              final tafsilot = _kunTafsiloti(lok);
              if (constraints.maxWidth > 640) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: kalendar),
                    const SizedBox(width: 24),
                    Expanded(child: tafsilot),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [kalendar, const SizedBox(height: 16), tafsilot],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kalendarVidjeti(Lokalizatsiya lok) {
    final oyBoshi = DateTime(_kalendarOy.year, _kalendarOy.month, 1);
    final oyOxiri = DateTime(_kalendarOy.year, _kalendarOy.month + 1, 0);
    final boshlanishOffset = oyBoshi.weekday - 1;
    final kunlarSoni = oyOxiri.day;
    final qatorSoni = ((boshlanishOffset + kunlarSoni) / 7).ceil();
    final bugun = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: lok.t('oldingi_oy'),
                onPressed: () => setState(() => _kalendarOy = DateTime(_kalendarOy.year, _kalendarOy.month - 1)),
              ),
              Text(
                '${lok.t("oy_${_kalendarOy.month}")} ${_kalendarOy.year}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: lok.t('keyingi_oy'),
                onPressed: () => setState(() => _kalendarOy = DateTime(_kalendarOy.year, _kalendarOy.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var h = 1; h <= 7; h++)
                Expanded(
                  child: Center(
                    child: Text(lok.t('hafta_$h'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var q = 0; q < qatorSoni; q++)
            Row(children: [for (var d = 0; d < 7; d++) _kunKatakchasi(q * 7 + d, boshlanishOffset, kunlarSoni, bugun)]),
        ],
      ),
    );
  }

  Widget _kunKatakchasi(int index, int offset, int kunlarSoni, DateTime bugun) {
    final kunRaqami = index - offset + 1;
    if (kunRaqami < 1 || kunRaqami > kunlarSoni) {
      return const Expanded(child: SizedBox(height: 36));
    }
    final kun = DateTime(_kalendarOy.year, _kalendarOy.month, kunRaqami);
    final bugunmi = _birXilKunmi(kun, bugun);
    final tanlanganmi = _tanlanganKun != null && _birXilKunmi(kun, _tanlanganKun!);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _kunTanlash(kun),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tanlanganmi ? kipTaroziYashil : null,
              border: bugunmi && !tanlanganmi ? Border.all(color: kipTaroziYashil) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$kunRaqami',
              style: TextStyle(
                color: tanlanganmi ? Colors.white : null,
                fontWeight: bugunmi ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kunTafsiloti(Lokalizatsiya lok) {
    if (_tanlanganKun == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(lok.t('kun_tanlang'), style: const TextStyle(color: Colors.grey)),
      );
    }
    if (_kunYuklanmoqda) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_kunXato != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_kunXato!, style: const TextStyle(color: Colors.red)),
      );
    }
    final kj = _kunlikJamlanma;
    if (kj == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kj.boshlanishSanasi, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        for (final kod in _mahsulotKodlari) _kunMahsulotQatori(kod, kj, lok),
        const Divider(height: 20),
        Text(
          '${lok.t("jami")}: ${kj.jamiSoni} ${lok.t("soni")} — ${kj.jamiKg.toStringAsFixed(1)} kg',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _kunMahsulotQatori(String kod, DavrJamlanmasi kj, Lokalizatsiya lok) {
    final mos = kj.mahsulotlar.where((e) => e.mahsulotKodi == kod);
    final soni = mos.isEmpty ? 0 : mos.first.soni;
    final kg = mos.isEmpty ? 0.0 : mos.first.jamiKg;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(lok.t(kod))),
          Expanded(child: Text('$soni ${lok.t("soni")} — ${kg.toStringAsFixed(1)} kg')),
        ],
      ),
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

  Widget _statKartasi(String sarlavha, String qiymat, IconData ikonka) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(ikonka, size: 32, color: kipTaroziYashil),
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
