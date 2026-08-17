import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../models/mahsulot.dart';
import '../../models/partiya.dart';
import '../../models/smena_holati.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/bekor_qilish_hisoblagichi.dart';
import '../../widgets/clock_widget.dart';
import '../../widgets/yuk_saqlanmadi_dialog.dart';

const _uuid = Uuid();

/// Partiyaning "to'lgan" deb hisoblanadigan nishon (target) kip soni —
/// Tola uchun 220, qolgan mahsulotlar uchun 210.
const _nishonSoni = {'tola': 220, 'lint': 210, 'pux': 210, 'ulyuk': 210};

int _nishon(String mahsulotKodi) => _nishonSoni[mahsulotKodi] ?? 210;

class _TortishYozuvi {
  final String mahsulotNomi;
  final double ogirlik;
  final DateTime vaqt;
  _TortishYozuvi({required this.mahsulotNomi, required this.ogirlik, required this.vaqt});
}

class OperatorEkrani extends StatefulWidget {
  const OperatorEkrani({super.key});

  @override
  State<OperatorEkrani> createState() => _OperatorEkraniState();
}

class _OperatorEkraniState extends State<OperatorEkrani> {
  List<Mahsulot> _mahsulotlar = [];
  Mahsulot? _tanlanganMahsulot;
  List<Partiya> _ochiqPartiyalar = [];
  Partiya? _tanlanganPartiya;
  SmenaHolati? _smenaHolati;

  final _partiyaRaqamiKontrolleri = TextEditingController();
  final _ogirlikKontrolleri = TextEditingController();
  final _ogirlikFokusi = FocusNode();

  bool _partiyaYuklanmoqda = false;
  bool _saqlashYuklanmoqda = false;
  Map<String, dynamic>? _oxirgiSaqlanganKip;

  // Shu sessiya davomida operator ishlatgan partiya raqamlari, mahsulot kodi
  // bo'yicha (eng yangisi birinchi) — backend'da alohida saqlanmaydi, faqat
  // qulaylik uchun frontend xotirasida kuzatiladi.
  final Map<String, List<int>> _songiPartiyalar = {};
  final List<_TortishYozuvi> _oxirgiTortishlar = [];

  Timer? _blokTimer;
  bool _blokDialogiKorinmoqda = false;

  @override
  void initState() {
    super.initState();
    _boshlangichniYuklash();
    _blokTimer = Timer.periodic(const Duration(seconds: 5), (_) => _blokniTekshirish());
    _ogirlikKontrolleri.addListener(_ogirlikOzgardi);
  }

  @override
  void dispose() {
    _blokTimer?.cancel();
    _ogirlikKontrolleri.removeListener(_ogirlikOzgardi);
    _partiyaRaqamiKontrolleri.dispose();
    _ogirlikKontrolleri.dispose();
    _ogirlikFokusi.dispose();
    super.dispose();
  }

  void _ogirlikOzgardi() {
    if (mounted) setState(() {});
  }

  AppState get _holat => context.read<AppState>();

  Future<void> _boshlangichniYuklash() async {
    try {
      final mahsulotlarJavob = await _holat.api.get('/mahsulotlar');
      setState(() => _mahsulotlar = (mahsulotlarJavob as List).map((e) => Mahsulot.fromJson(e)).toList());
      await _smenaHolatiniYangilash();
      await _blokniTekshirish();
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  Future<void> _smenaHolatiniYangilash() async {
    try {
      final javob = await _holat.api.get('/kiplar/smena/holati');
      if (mounted) setState(() => _smenaHolati = SmenaHolati.fromJson(javob));
    } catch (_) {
      // Jimgina o'tkazib yuboriladi — bosh sahifa ma'lumoti hal qiluvchi emas
    }
  }

  Future<void> _blokniTekshirish() async {
    try {
      final javob = await _holat.api.get('/shubhali-holatlar/bloklovchi');
      if (javob != null && !_blokDialogiKorinmoqda && mounted) {
        _blokDialogiKorinmoqda = true;
        await yukSaqlanmadiDialogniKorsat(
          context: context,
          lok: _holat.lok,
          onTushundim: () async {
            try {
              await _holat.api.patch('/shubhali-holatlar/${javob['id']}/tasdiqla');
            } catch (e) {
              _xatoKorsat(e.toString());
            }
          },
        );
        _blokDialogiKorinmoqda = false;
      }
    } catch (_) {
      // Aloqa muammosi — keyingi tsiklda qayta uriniladi
    }
  }

  Future<void> _mahsulotTanlash(Mahsulot mahsulot) async {
    setState(() {
      _tanlanganMahsulot = mahsulot;
      _tanlanganPartiya = null;
      _ochiqPartiyalar = [];
      _partiyaRaqamiKontrolleri.clear();
    });
    await _ochiqPartiyalarniYangilash();
  }

  /// Kip saqlangandan keyin partiya progressini (kip_soni/jami_kg) yangilaydi —
  /// _mahsulotTanlash'dan farqli, joriy tanlangan partiyani BEKOR QILMAYDI,
  /// aks holda operator har kip saqlagandan keyin partiya raqamini qayta
  /// kiritishga majbur bo'lardi.
  Future<void> _ochiqPartiyalarniYangilash() async {
    if (_tanlanganMahsulot == null) return;
    try {
      final javob = await _holat.api.get('/partiyalar/ochiq', query: {'mahsulot_kodi': _tanlanganMahsulot!.kod});
      final yangilangan = (javob as List).map((e) => Partiya.fromJson(e)).toList();
      setState(() {
        _ochiqPartiyalar = yangilangan;
        if (_tanlanganPartiya != null) {
          final mos = yangilangan.where((p) => p.id == _tanlanganPartiya!.id);
          if (mos.isNotEmpty) _tanlanganPartiya = mos.first;
        }
      });
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  Future<void> _partiyaniOchish() async {
    final matn = _partiyaRaqamiKontrolleri.text.trim();
    if (_tanlanganMahsulot == null) return;
    if (matn.isEmpty) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }
    final raqam = int.tryParse(matn);
    if (raqam == null || raqam < 1) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }

    setState(() => _partiyaYuklanmoqda = true);
    try {
      final javob = await _holat.api
          .post('/partiyalar', tana: {'mahsulot_kodi': _tanlanganMahsulot!.kod, 'partiya_raqami': raqam});
      final partiya = Partiya.fromJson(javob);
      setState(() {
        _tanlanganPartiya = partiya;
        if (!_ochiqPartiyalar.any((p) => p.id == partiya.id)) _ochiqPartiyalar = [..._ochiqPartiyalar, partiya];
        _songiPartiyaniEslash(partiya.mahsulotKodi, partiya.partiyaRaqami);
      });
      _ogirlikFokusi.requestFocus();
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted) setState(() => _partiyaYuklanmoqda = false);
    }
  }

  void _songiPartiyaniEslash(String mahsulotKodi, int raqam) {
    final royxat = _songiPartiyalar.putIfAbsent(mahsulotKodi, () => []);
    royxat.remove(raqam);
    royxat.insert(0, raqam);
    if (royxat.length > 5) royxat.removeRange(5, royxat.length);
  }

  void _partiyaniTanlash(Partiya partiya) {
    setState(() {
      _tanlanganPartiya = partiya;
      _partiyaRaqamiKontrolleri.text = partiya.partiyaRaqami.toString();
    });
    _ogirlikFokusi.requestFocus();
  }

  void _songiPartiyaTanlandi(int raqam) {
    _partiyaRaqamiKontrolleri.text = raqam.toString();
    _partiyaniOchish();
  }

  Future<void> _saqlash({bool majburiy = false}) async {
    if (_tanlanganPartiya == null) {
      _xatoKorsat(_holat.lok.t('partiya_majburiy'));
      return;
    }
    final ogirlik = double.tryParse(_ogirlikKontrolleri.text.replaceAll(',', '.'));
    if (ogirlik == null || ogirlik <= 0) {
      _xatoKorsat(_holat.lok.t('ogirlik_kiriting'));
      return;
    }

    setState(() => _saqlashYuklanmoqda = true);
    final tana = {
      'mijoz_id': _uuid.v4(),
      'partiya_id': _tanlanganPartiya!.id,
      'ogirlik': ogirlik,
      'mahalliy_vaqt': DateTime.now().toUtc().toIso8601String(),
      'majburiy': majburiy,
      if (ApiClient.stansiyaId != null) 'stansiya_id': ApiClient.stansiyaId,
    };

    try {
      final javob = await _holat.api.post('/kiplar', tana: tana);
      if (!mounted) return;
      setState(() {
        _oxirgiSaqlanganKip = javob;
        _oxirgiTortishlar.insert(
          0,
          _TortishYozuvi(mahsulotNomi: _tanlanganMahsulot!.nomi, ogirlik: ogirlik, vaqt: DateTime.now()),
        );
        if (_oxirgiTortishlar.length > 2) _oxirgiTortishlar.removeRange(2, _oxirgiTortishlar.length);
        _ogirlikKontrolleri.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_holat.lok.t('kip_saqlandi'))));
      _ogirlikFokusi.requestFocus();
      await _smenaHolatiniYangilash();
      await _ochiqPartiyalarniYangilash();
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.tafsilot is Map && e.tafsilot['avvalgi_kip_id'] != null) {
        _dublikatOgohlantirishKorsat();
      } else {
        _xatoKorsat(e.xabar);
      }
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted) setState(() => _saqlashYuklanmoqda = false);
    }
  }

  void _dublikatOgohlantirishKorsat() {
    final lok = _holat.lok;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(lok.t('dublikat_sarlavha')),
        content: Text(lok.t('dublikat_matn')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(lok.t('yoq_bekor'))),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _saqlash(majburiy: true);
            },
            child: Text(lok.t('ha_yangi_kip')),
          ),
        ],
      ),
    );
  }

  Future<void> _bekorQilish() async {
    if (_oxirgiSaqlanganKip == null) return;
    try {
      await _holat.api.post('/kiplar/${_oxirgiSaqlanganKip!['id']}/bekor-qilish');
      setState(() => _oxirgiSaqlanganKip = null);
      await _smenaHolatiniYangilash();
      await _ochiqPartiyalarniYangilash();
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  void _xatoKorsat(String xabar) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(xabar), backgroundColor: Colors.red.shade700));
  }

  /// Hozircha real qurilma (RS232/kamera/server) ulanish holati kuzatilmagani
  /// uchun statik "ulangan" qaytaradi — struktura tayyor, real qiymat
  /// keyinchalik shu yerga ulanadi.
  bool _qurilmaUlanganmi() => true;

  MahsulotBoyichaHolat? _mahsulotHolati(String kod) {
    if (_smenaHolati == null) return null;
    for (final m in _smenaHolati!.mahsulotlar) {
      if (m.mahsulotKodi == kod) return m;
    }
    return null;
  }

  String _vaqtQisqa(DateTime v) {
    String ikki(int s) => s.toString().padLeft(2, '0');
    return '${ikki(v.hour)}:${ikki(v.minute)}:${ikki(v.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.scale),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Kip Tarozi — ${lok.t("smena")} ${holat.foydalanuvchi?.smena ?? ""}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          _ulanishIkonkasi(Icons.dns_rounded, lok.t('server'), lok),
          _ulanishIkonkasi(Icons.videocam_rounded, lok.t('kamera'), lok),
          _ulanishIkonkasi(Icons.monitor_weight_rounded, lok.t('tarozi'), lok),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Center(child: SoatWidget())),
          IconButton(
            icon: Icon(holat.temaRejimi == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => holat.temaniAlmashtirish(),
          ),
          TextButton(
            onPressed: () => holat.tilniAlmashtirish(),
            child: Text(holat.til.name.toUpperCase(), style: const TextStyle(color: Colors.white)),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => holat.chiqish()),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 38, child: _chapPanel(lok)),
                const VerticalDivider(width: 1),
                Expanded(flex: 62, child: _ongPanel(lok)),
              ],
            ),
          ),
          _oxirgiTortishlarQatori(lok),
        ],
      ),
    );
  }

  Widget _ulanishIkonkasi(IconData ikonka, String nomi, dynamic lok) {
    final ulanganmi = _qurilmaUlanganmi();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: '$nomi: ${ulanganmi ? lok.t("ulangan") : lok.t("ulanmagan")}',
        child: Icon(ikonka, size: 20, color: ulanganmi ? Colors.greenAccent.shade400 : Colors.red.shade300),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Chap panel: mahsulot tanlash, partiya ochish, joriy partiya progressi
  // ---------------------------------------------------------------------

  Widget _chapPanel(dynamic lok) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lok.t('mahsulot'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _mahsulotGridi(lok),
          const SizedBox(height: 20),
          if (_tanlanganMahsulot != null) ...[
            TextField(
              controller: _partiyaRaqamiKontrolleri,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: lok.t('partiya_raqami'), border: const OutlineInputBorder()),
              onSubmitted: (_) => _partiyaniOchish(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _partiyaYuklanmoqda ? null : _partiyaniOchish,
                child: _partiyaYuklanmoqda
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(lok.t('partiya_ochish')),
              ),
            ),
            _songiPartiyalarQismi(lok),
            if (_ochiqPartiyalar.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(lok.t('ochiq_partiyalar'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _ochiqPartiyalar
                    .map(
                      (p) => ActionChip(
                        label: Text('#${p.partiyaRaqami} (${p.kipSoni}/${_nishon(p.mahsulotKodi)})'),
                        backgroundColor: _tanlanganPartiya?.id == p.id ? kipTaroziYashil.withValues(alpha: 0.2) : null,
                        onPressed: () => _partiyaniTanlash(p),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (_tanlanganPartiya != null) ...[
              const SizedBox(height: 20),
              _partiyaProgressPaneli(lok),
            ],
          ],
        ],
      ),
    );
  }

  Widget _mahsulotGridi(dynamic lok) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: _mahsulotlar.map((m) => _mahsulotTugmasi(m)).toList(),
    );
  }

  Widget _mahsulotTugmasi(Mahsulot m) {
    final tanlanganmi = _tanlanganMahsulot?.id == m.id;
    if (tanlanganmi) {
      return ElevatedButton(
        onPressed: () => _mahsulotTanlash(m),
        style: ElevatedButton.styleFrom(backgroundColor: kipTaroziYashil, foregroundColor: Colors.white),
        child: Text(m.nomi, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
    }
    return OutlinedButton(
      onPressed: () => _mahsulotTanlash(m),
      style: OutlinedButton.styleFrom(side: const BorderSide(color: kipTaroziYashil)),
      child: Text(m.nomi, style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _songiPartiyalarQismi(dynamic lok) {
    final royxat = _songiPartiyalar[_tanlanganMahsulot?.kod] ?? [];
    if (royxat.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lok.t('song_ishlatilganlar'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: royxat
                .map((raqam) => ActionChip(label: Text('#$raqam'), onPressed: () => _songiPartiyaTanlandi(raqam)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _partiyaProgressPaneli(dynamic lok) {
    final p = _tanlanganPartiya!;
    final nishon = _nishon(p.mahsulotKodi);
    final progress = (p.kipSoni / nishon).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${lok.t("progress")}: #${p.partiyaRaqami} — ${p.kipSoni}/$nishon',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: kipTaroziYashil,
              ),
            ),
            const SizedBox(height: 4),
            Text('${p.jamiKg.toStringAsFixed(1)} kg', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // O'ng panel: barqarorlik, og'irlik ko'rsatkichi, saqlash, smena holati
  // ---------------------------------------------------------------------

  Widget _ongPanel(dynamic lok) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tanlanganPartiya == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('—')))
          else ...[
            _barqarorlikKorsatkichi(lok),
            const SizedBox(height: 16),
            _ogirlikKorsatkichi(lok),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _saqlashYuklanmoqda ? null : () => _saqlash(),
                icon: _saqlashYuklanmoqda
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 26),
                label: Text(lok.t('saqlash'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_oxirgiSaqlanganKip != null) ...[
              const SizedBox(height: 20),
              Center(
                child: BekorQilishHisoblagichi(
                  key: ValueKey(_oxirgiSaqlanganKip!['id']),
                  muddatSoniya: 30,
                  matn: lok.t('bekor_qilish'),
                  onBekorQilish: _bekorQilish,
                  onMuddatTugadi: () => setState(() => _oxirgiSaqlanganKip = null),
                ),
              ),
            ],
          ],
          const SizedBox(height: 28),
          Text(lok.t('smena_holati'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _smenaHolatiKartalari(lok),
        ],
      ),
    );
  }

  Widget _barqarorlikKorsatkichi(dynamic lok) {
    final qiymat = double.tryParse(_ogirlikKontrolleri.text.replaceAll(',', '.'));
    final barqarormi = qiymat != null && qiymat > 0;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: barqarormi ? Colors.green : Colors.orange, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          barqarormi ? lok.t('barqaror') : lok.t('kutilmoqda'),
          style: TextStyle(
            color: barqarormi ? Colors.green.shade700 : Colors.orange.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _ogirlikKorsatkichi(dynamic lok) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: _ogirlikKontrolleri,
        focusNode: _ogirlikFokusi,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: kipTaroziYashil),
        decoration: InputDecoration(
          hintText: '0.0',
          suffixText: ' kg',
          suffixStyle: const TextStyle(fontSize: 26, color: Colors.grey),
          border: InputBorder.none,
          isCollapsed: true,
        ),
        onSubmitted: (_) => _saqlashYuklanmoqda ? null : _saqlash(),
      ),
    );
  }

  Widget _smenaHolatiKartalari(dynamic lok) {
    if (_mahsulotlar.isEmpty) return const Text('—');
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.1,
      children: _mahsulotlar.map((m) {
        final h = _mahsulotHolati(m.kod);
        return Card(
          color: kipTaroziYashil.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m.nomi, style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('${h?.soni ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('${(h?.jamiKg ?? 0).toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------
  // Pastki chiziq: oxirgi 2 ta tortish
  // ---------------------------------------------------------------------

  Widget _oxirgiTortishlarQatori(dynamic lok) {
    if (_oxirgiTortishlar.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          Text(
            lok.t('oxirgi_tortishlar'),
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Wrap(
              spacing: 28,
              runSpacing: 4,
              children: _oxirgiTortishlar
                  .map(
                    (t) => Text(
                      '${t.mahsulotNomi} — ${t.ogirlik.toStringAsFixed(1)} kg — ${_vaqtQisqa(t.vaqt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
