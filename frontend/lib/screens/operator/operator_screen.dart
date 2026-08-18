import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../api/api_client.dart';
import '../../api/api_exception.dart';
import '../../models/mahsulot.dart';
import '../../models/partiya.dart';
import '../../models/smena_holati.dart';
import '../../services/fayl_yuklab_olish.dart';
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
  bool _excelYuklanmoqda = false;
  Map<String, dynamic>? _oxirgiSaqlanganKip;

  // Og'irlik ko'rsatkichining rang-signal holati: tarozida yuk bormi (yashil)
  // yoki yo'qmi (qizil). Saqlash bosilgandan keyin maydon tozalanadi, lekin
  // signal yashil bo'lib qolishi kerak — shuning uchun bu holat alohida
  // saqlanadi, faqat _ogirlikKontrolleri matnidan har safar hisoblanmaydi.
  bool _yukBor = false;
  bool _dasturiyTozalash = false;

  bool _smenaRoyxatiYuklanmoqda = false;
  List<Map<String, dynamic>> _smenaRoyxati = [];

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
    // Dasturiy tozalash (saqlashdan keyin) signalni qizilga qaytarmasligi
    // kerak — faqat operatorning o'zi kiritgan/tozalagan holatlarda signal
    // qayta hisoblanadi.
    if (!_dasturiyTozalash) {
      final qiymat = double.tryParse(_ogirlikKontrolleri.text.replaceAll(',', '.'));
      _yukBor = qiymat != null && qiymat > 0;
    }
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
      _smenaRoyxati = [];
      _yukBor = false;
    });
    await Future.wait([_ochiqPartiyalarniYangilash(), _smenaRoyxatiniYangilash()]);
  }

  /// Tanlangan mahsulot bo'yicha, joriy smenada, bugun tortilgan kiplar
  /// ro'yxatini yuklaydi — mahsulot tugmasi ostidagi qisqa tarix panelini
  /// to'ldirish uchun.
  Future<void> _smenaRoyxatiniYangilash() async {
    final soralganMahsulot = _tanlanganMahsulot;
    if (soralganMahsulot == null) return;
    setState(() => _smenaRoyxatiYuklanmoqda = true);
    try {
      final javob = await _holat.api.get('/kiplar/smena/royxat', query: {'mahsulot_kodi': soralganMahsulot.kod});
      // Operator javob kutilayotganda boshqa mahsulotga o'tib ketgan bo'lishi
      // mumkin — eskirgan javobni e'tiborsiz qoldiramiz.
      if (_tanlanganMahsulot?.id != soralganMahsulot.id) return;
      setState(() => _smenaRoyxati = (javob as List).cast<Map<String, dynamic>>());
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted && _tanlanganMahsulot?.id == soralganMahsulot.id) {
        setState(() => _smenaRoyxatiYuklanmoqda = false);
      }
    }
  }

  /// Kip saqlangandan keyin partiya progressini (kip_soni/jami_kg) yangilaydi —
  /// _mahsulotTanlash'dan farqli, joriy tanlangan partiyani BEKOR QILMAYDI,
  /// aks holda operator har kip saqlagandan keyin partiya raqamini qayta
  /// kiritishga majbur bo'lardi.
  Future<void> _ochiqPartiyalarniYangilash() async {
    final soralganMahsulot = _tanlanganMahsulot;
    if (soralganMahsulot == null) return;
    try {
      final javob = await _holat.api.get('/partiyalar/ochiq', query: {'mahsulot_kodi': soralganMahsulot.kod});
      // Operator javob kutilayotganda boshqa mahsulotga o'tib ketgan bo'lishi
      // mumkin — bunday holda eskirgan javobni e'tiborsiz qoldiramiz, aks
      // holda ro'yxat boshqa mahsulotning partiyalari bilan aralashib qoladi.
      if (_tanlanganMahsulot?.id != soralganMahsulot.id) return;
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
      _dasturiyTozalash = true;
      _ogirlikKontrolleri.clear();
      _dasturiyTozalash = false;
      setState(() {
        _oxirgiSaqlanganKip = javob;
        _oxirgiTortishlar.insert(
          0,
          _TortishYozuvi(mahsulotNomi: _tanlanganMahsulot!.nomi, ogirlik: ogirlik, vaqt: DateTime.now()),
        );
        if (_oxirgiTortishlar.length > 2) _oxirgiTortishlar.removeRange(2, _oxirgiTortishlar.length);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_holat.lok.t('kip_saqlandi'))));
      _ogirlikFokusi.requestFocus();
      await _smenaHolatiniYangilash();
      await _ochiqPartiyalarniYangilash();
      await _smenaRoyxatiniYangilash();
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
      await _smenaRoyxatiniYangilash();
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  Future<void> _excelYuklab() async {
    final smena = _holat.foydalanuvchi?.smena;
    if (smena == null) return;

    setState(() => _excelYuklanmoqda = true);
    try {
      final sana = DateTime.now().toIso8601String().substring(0, 10);
      final baytlar = await _holat.api.getBaytlar('/hisobotlar/smena-excel', query: {'sana': sana, 'smena': smena});
      faylniSaqlash(baytlar, 'Smena_${smena}_$sana.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_holat.lok.t('fayl_yuklab_olindi'))));
      }
    } on ApiException catch (e) {
      _xatoKorsat(e.xabar);
    } catch (e) {
      _xatoKorsat(e.toString());
    } finally {
      if (mounted) setState(() => _excelYuklanmoqda = false);
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
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Tooltip(
        message: '$nomi: ${ulanganmi ? lok.t("ulangan") : lok.t("ulanmagan")}',
        child: Icon(ikonka, size: 28, color: ulanganmi ? Colors.greenAccent : Colors.redAccent.shade100),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Chap panel: mahsulot tanlash, partiya ochish, joriy partiya progressi
  // ---------------------------------------------------------------------

  Widget _chapPanel(dynamic lok) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lok.t('mahsulot'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          _mahsulotGridi(lok),
          if (_tanlanganMahsulot != null) _smenaTarixiRoyxati(lok),
          if (_tanlanganMahsulot != null)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _partiyaRaqamiKontrolleri,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: lok.t('partiya_raqami'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _partiyaniOchish(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
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
                      const SizedBox(height: 12),
                      Text(lok.t('ochiq_partiyalar'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ochiqPartiyalar
                            .map(
                              (p) => ActionChip(
                                label: Text('#${p.partiyaRaqami} (${p.kipSoni}/${_nishon(p.mahsulotKodi)})'),
                                backgroundColor:
                                    _tanlanganPartiya?.id == p.id ? kipTaroziYashil.withValues(alpha: 0.2) : null,
                                onPressed: () => _partiyaniTanlash(p),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (_tanlanganPartiya != null) ...[
                      const SizedBox(height: 12),
                      _partiyaProgressPaneli(lok),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _mahsulotGridi(dynamic lok) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.6,
      children: _mahsulotlar.map((m) => _mahsulotTugmasi(m)).toList(),
    );
  }

  /// Tanlangan mahsulot tugmasi ostidagi qisqa smena-tarixi paneli — shu
  /// smenada, bugun, shu mahsulot bo'yicha tortilgan kiplar ro'yxati.
  Widget _smenaTarixiRoyxati(dynamic lok) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                lok.t('smena_tarixi'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
              const Spacer(),
              if (_smenaRoyxatiYuklanmoqda)
                const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: _smenaRoyxati.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lok.t('tarix_yoq'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _smenaRoyxati.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, i) {
                      final y = _smenaRoyxati[i];
                      final bekorMi = y['holati'] != 'aktiv';
                      final chiziq = bekorMi ? TextDecoration.lineThrough : null;
                      final rangi = bekorMi ? Colors.grey.shade400 : null;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '#${y['kip_raqami']}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, decoration: chiziq, color: rangi),
                              ),
                            ),
                            SizedBox(
                              width: 54,
                              child: Text(
                                _vaqtQisqa(DateTime.parse(y['vaqt'] as String).toLocal()),
                                style: TextStyle(fontSize: 11, color: rangi ?? Colors.grey),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${(y['ogirlik'] as num).toStringAsFixed(1)} kg',
                                textAlign: TextAlign.right,
                                style: TextStyle(fontSize: 12, decoration: chiziq, color: rangi),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tanlanganPartiya != null) ...[
            _ogirlikBirlashganKorsatkichi(lok),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _saqlashYuklanmoqda ? null : () => _saqlash(),
                icon: _saqlashYuklanmoqda
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 20),
                label: Text(lok.t('saqlash'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_oxirgiSaqlanganKip != null) ...[
              const SizedBox(height: 8),
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
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final surat = _suratPaneli(lok);
                final smena = _smenaBolimi(lok);
                if (constraints.maxWidth > 640) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 45, child: surat),
                      const SizedBox(width: 16),
                      Expanded(flex: 55, child: SingleChildScrollView(child: smena)),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [surat, const SizedBox(height: 16), smena],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Og'irlik ko'rsatkichi + rang-signal — bittalashtirilgan: tarozi 0 kg
  /// bo'lsa QIZIL ("Kutilmoqda"), yuk qo'yilib >0 bo'lsa YASHIL ("Barqaror")
  /// va shu holat Saqlash bosilgandan keyin ham (maydon tozalangan bo'lsa
  /// ham) yashil bo'lib qoladi — kip olib tashlanib qayta 0 ga tushgandagina
  /// yana qizilga qaytadi. Bu avvalgi alohida "Kutilmoqda/Barqaror"
  /// bannerini ham o'zida mujassam etadi, ular bir-biriga zid emas.
  Widget _ogirlikBirlashganKorsatkichi(dynamic lok) {
    final MaterialColor rang = _yukBor ? Colors.green : Colors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: rang.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rang, width: 2.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_yukBor ? Icons.check_circle : Icons.hourglass_top, color: rang.shade700, size: 18),
              const SizedBox(width: 6),
              Text(
                _yukBor ? lok.t('barqaror') : lok.t('kutilmoqda'),
                style: TextStyle(color: rang.shade700, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          TextField(
            controller: _ogirlikKontrolleri,
            focusNode: _ogirlikFokusi,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 58, fontWeight: FontWeight.bold, color: rang.shade700),
            decoration: InputDecoration(
              hintText: '0.0',
              suffixText: ' kg',
              suffixStyle: const TextStyle(fontSize: 20, color: Colors.grey),
              border: InputBorder.none,
              isCollapsed: true,
            ),
            onSubmitted: (_) => _saqlashYuklanmoqda ? null : _saqlash(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // So'nggi tortilgan kip surati — "Smena joriy holati" yonida
  // ---------------------------------------------------------------------

  Widget _suratPaneli(dynamic lok) {
    final suratYoli = _oxirgiSaqlanganKip?['surat_yoli'] as String?;
    return LayoutBuilder(
      builder: (context, constraints) {
        const boshliqBalandligi = 26.0;
        final maxBalandlik =
            constraints.maxHeight.isFinite ? constraints.maxHeight - boshliqBalandligi : constraints.maxWidth;
        final andoza = math.min(constraints.maxWidth, maxBalandlik).clamp(80.0, 480.0);

        Widget ichki;
        if (_oxirgiSaqlanganKip == null) {
          ichki = _suratPlaceholder(Icons.photo_camera_outlined, lok.t('hali_kip_saqlanmagan'), andoza);
        } else if (suratYoli == null || suratYoli.isEmpty) {
          ichki = _suratPlaceholder(Icons.image_not_supported_outlined, lok.t('surat_yoq'), andoza);
        } else {
          ichki = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              suratYoli,
              key: ValueKey(suratYoli),
              width: andoza,
              height: andoza,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  width: andoza,
                  height: andoza,
                  color: Colors.grey.shade100,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  _suratPlaceholder(Icons.broken_image_outlined, lok.t('surat_yuklanmadi'), andoza),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lok.t('songgi_kip_surati'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Center(child: SizedBox(width: andoza, height: andoza, child: ichki)),
          ],
        );
      },
    );
  }

  Widget _suratPlaceholder(IconData ikonka, String matn, double andoza) {
    return Container(
      width: andoza,
      height: andoza,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikonka, color: Colors.grey.shade400, size: 36),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(matn, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Smena joriy holati
  // ---------------------------------------------------------------------

  Widget _smenaBolimi(dynamic lok) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(lok.t('smena_holati'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                onPressed: _excelYuklanmoqda ? null : _excelYuklab,
                icon: _excelYuklanmoqda
                    ? const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download, size: 15),
                label: Text(lok.t('excel_yuklab_olish'), style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _smenaHolatiKartalari(lok),
      ],
    );
  }

  Widget _smenaHolatiKartalari(dynamic lok) {
    if (_mahsulotlar.isEmpty) return const Text('—');
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: _mahsulotlar.map((m) {
        final h = _mahsulotHolati(m.kod);
        return Card(
          margin: EdgeInsets.zero,
          color: kipTaroziYashil.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(m.nomi, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('${h?.soni ?? 0}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('${(h?.jamiKg ?? 0).toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
