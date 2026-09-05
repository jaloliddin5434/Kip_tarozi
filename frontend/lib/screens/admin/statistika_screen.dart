import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../i18n/strings.dart';
import '../../models/dashboard.dart';
import '../../models/statistika.dart';
import '../../services/statistika_pdf.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/kalendar_vidjeti.dart';

const _mahsulotKodlari = ['tola', 'lint', 'pux', 'ulyuk'];
const _smenaHarflari = ['A', 'B', 'C', 'D'];

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
          _mahsulotFiltrQatori(lok),
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

  /// Mahsulot filtri — davr/smena qatorlaridan farqli, har bir mahsulot
  /// o'zining brend rangida (operator/dashboard ekranlarida ishlatilgan
  /// `mahsulotRangi` bilan izchil): tanlangan — to'liq shu rang bilan
  /// to'ldirilgan, tanlanmagan — shu rang bilan chegaralangan.
  Widget _mahsulotFiltrQatori(Lokalizatsiya lok) {
    return Row(
      children: [
        for (final kod in _mahsulotKodlari)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _mahsulotTugmasi(lok.t(kod), kod),
            ),
          ),
      ],
    );
  }

  Widget _mahsulotTugmasi(String matn, String kod) {
    final tanlanganmi = _mahsulot == kod;
    final rang = mahsulotRangi(kod);
    void tanlash() {
      setState(() => _mahsulot = kod);
      _yuklash();
    }

    return SizedBox(
      height: 44,
      child: tanlanganmi
          ? ElevatedButton(
              onPressed: tanlash,
              style: ElevatedButton.styleFrom(backgroundColor: rang, foregroundColor: Colors.white),
              child: Text(matn, overflow: TextOverflow.ellipsis),
            )
          : OutlinedButton(
              onPressed: tanlash,
              style: OutlinedButton.styleFrom(side: BorderSide(color: rang), foregroundColor: rang),
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
              _jamiKartasi(lok.t('jami'), '$soni ${lok.t("soni")}', Icons.inventory_2),
              _statKartasi('${lok.t("jami")} (kg)', '${kg.toStringAsFixed(1)} kg', Icons.scale),
              _statKartasi(lok.t('ortacha_ogirlik'), '${ortacha.toStringAsFixed(1)} kg', Icons.balance),
            ],
          ),
          const SizedBox(height: 24),
          if (_smena == null) ...[
            Text(lok.t('smenalar_taqqoslash'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            _smenaReytingi(_smenalar, lok),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(lok.t('kunlar_boyicha'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final kalendar = KalendarVidjeti(tanlanganKun: _tanlanganKun, onKunTanlash: _kunTanlash);
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

  // ---------------------------------------------------------------------
  // Smenalar taqqoslash grafigi
  // ---------------------------------------------------------------------

  /// HAR DOIM 4 ta qator (A/B/C/D) ko'rsatadi, qiymat bo'yicha KAMAYISH
  /// tartibida saralangan (eng ko'p tortgan smena eng yuqorida). Har bir
  /// qator: chapda smena nomi, o'ngda qiymat (kg), pastda eng katta
  /// qiymatga nisbatan proportsional kenglikdagi progress-chiziq.
  Widget _smenaReytingi(List<SmenaJamlanmasi> xom, Lokalizatsiya lok) {
    final xarita = {for (final s in xom) s.smena: s};
    final tugallangan = [
      for (final harf in _smenaHarflari) xarita[harf] ?? SmenaJamlanmasi(smena: harf, soni: 0, jamiKg: 0),
    ]..sort((a, b) => b.jamiKg.compareTo(a.jamiKg));

    final maxKg = tugallangan.first.jamiKg;

    return Column(
      children: [
        for (var i = 0; i < tugallangan.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _smenaReytingQatori(tugallangan[i], maxKg: maxKg, birinchimi: i == 0, lok: lok),
        ],
      ],
    );
  }

  Widget _smenaReytingQatori(
    SmenaJamlanmasi s, {
    required double maxKg,
    required bool birinchimi,
    required Lokalizatsiya lok,
  }) {
    final malumotBormi = s.soni > 0;
    final ulush = malumotBormi && maxKg > 0 ? (s.jamiKg / maxKg).clamp(0.0, 1.0) : 0.0;
    final eslatilganmi = birinchimi && malumotBormi;
    final matnRangi = !malumotBormi
        ? Colors.grey.shade500
        : eslatilganmi
            ? kipTaroziYashil
            : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${lok.t("smena")} ${s.smena}',
              style: TextStyle(fontSize: 14, fontWeight: eslatilganmi ? FontWeight.bold : FontWeight.w500, color: matnRangi),
            ),
            Text(
              '${s.jamiKg.toStringAsFixed(1)} kg',
              style: TextStyle(fontSize: 14, fontWeight: eslatilganmi ? FontWeight.bold : FontWeight.w500, color: matnRangi),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 10,
          child: Stack(
            // StackFit.expand — aks holda fon (track) Container'i o'lchamsiz
            // qolib, 0x0 gacha yig'ilib ko'rinmay qolishi mumkin edi.
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
              ),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ulush,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: eslatilganmi
                        ? const LinearGradient(colors: [Color(0xFF0F6E56), Color(0xFF1D9E75)])
                        : null,
                    color: eslatilganmi ? null : (malumotBormi ? kipTaroziYashil.withValues(alpha: 0.55) : null),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Davr xulosasi kartalari — Dashboard ekranidagi uslub bilan bir xil
  // ---------------------------------------------------------------------

  Widget _jamiKartasi(String sarlavha, String qiymat, IconData ikonka) {
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
          Icon(ikonka, size: 30, color: Colors.white),
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

  Widget _statKartasi(String sarlavha, String qiymat, IconData ikonka) {
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
          Icon(ikonka, size: 30, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sarlavha, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(qiymat, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
