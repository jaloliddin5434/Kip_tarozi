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

  Timer? _blokTimer;
  bool _blokDialogiKorinmoqda = false;

  @override
  void initState() {
    super.initState();
    _boshlangichniYuklash();
    _blokTimer = Timer.periodic(const Duration(seconds: 5), (_) => _blokniTekshirish());
  }

  @override
  void dispose() {
    _blokTimer?.cancel();
    _partiyaRaqamiKontrolleri.dispose();
    _ogirlikKontrolleri.dispose();
    _ogirlikFokusi.dispose();
    super.dispose();
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
      });
      _ogirlikFokusi.requestFocus();
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted) setState(() => _partiyaYuklanmoqda = false);
    }
  }

  void _partiyaniTanlash(Partiya partiya) {
    setState(() {
      _tanlanganPartiya = partiya;
      _partiyaRaqamiKontrolleri.text = partiya.partiyaRaqami.toString();
    });
    _ogirlikFokusi.requestFocus();
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
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Center(child: SoatWidget())),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _smenaHolatiPaneli(lok),
            const SizedBox(height: 16),
            _mahsulotTugmalari(lok),
            const SizedBox(height: 16),
            Expanded(child: _asosiyIshOraligi(lok)),
          ],
        ),
      ),
    );
  }

  Widget _smenaHolatiPaneli(dynamic lok) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text(lok.t('smena_holati'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            Expanded(
              child: _smenaHolati == null || _smenaHolati!.mahsulotlar.isEmpty
                  ? const Text('—')
                  : Wrap(
                      spacing: 20,
                      children: _smenaHolati!.mahsulotlar
                          .map((m) => Text('${m.mahsulotNomi}: ${m.soni} ${lok.t("soni")} / ${m.jamiKg.toStringAsFixed(1)} kg'))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mahsulotTugmalari(dynamic lok) {
    return Wrap(
      spacing: 12,
      children: _mahsulotlar.map((m) {
        final tanlanganmi = _tanlanganMahsulot?.id == m.id;
        return ChoiceChip(
          label: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(m.nomi, style: const TextStyle(fontSize: 16))),
          selected: tanlanganmi,
          selectedColor: kipTaroziYashil,
          labelStyle: TextStyle(color: tanlanganmi ? Colors.white : null, fontWeight: FontWeight.bold),
          onSelected: (_) => _mahsulotTanlash(m),
        );
      }).toList(),
    );
  }

  Widget _asosiyIshOraligi(dynamic lok) {
    if (_tanlanganMahsulot == null) {
      return Center(child: Text(lok.t('mahsulot')));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_ochiqPartiyalar.isNotEmpty) ...[
            Text(lok.t('progress'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _ochiqPartiyalar
                  .map((p) => ActionChip(
                        label: Text('#${p.partiyaRaqami} (${p.kipSoni} ${lok.t("soni")} / ${p.jamiKg.toStringAsFixed(1)} kg)'),
                        backgroundColor: _tanlanganPartiya?.id == p.id ? kipTaroziYashil.withValues(alpha: 0.2) : null,
                        onPressed: () => _partiyaniTanlash(p),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _partiyaRaqamiKontrolleri,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: lok.t('partiya_raqami'), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _partiyaniOchish(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _partiyaYuklanmoqda ? null : _partiyaniOchish,
                child: Text(lok.t('partiya_ochish')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_tanlanganPartiya != null) ...[
            Text('${lok.t("progress")}: #${_tanlanganPartiya!.partiyaRaqami} — ${_tanlanganPartiya!.kipSoni} ${lok.t("soni")} / ${_tanlanganPartiya!.jamiKg.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _ogirlikKontrolleri,
                focusNode: _ogirlikFokusi,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                decoration: InputDecoration(labelText: lok.t('ogirlik'), helperText: lok.t('ogirlik_kiriting'), border: const OutlineInputBorder()),
                onSubmitted: (_) => _saqlashYuklanmoqda ? null : _saqlash(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saqlashYuklanmoqda ? null : () => _saqlash(),
              icon: _saqlashYuklanmoqda
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(lok.t('saqlash'), style: const TextStyle(fontSize: 18)),
            ),
            if (_oxirgiSaqlanganKip != null) ...[
              const SizedBox(height: 16),
              BekorQilishHisoblagichi(
                key: ValueKey(_oxirgiSaqlanganKip!['id']),
                muddatSoniya: 30,
                matn: lok.t('bekor_qilish'),
                onBekorQilish: _bekorQilish,
                onMuddatTugadi: () => setState(() => _oxirgiSaqlanganKip = null),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
