import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../models/hujjat.dart';
import '../../models/partiya.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/partiya_batafsil_dialog.dart';

/// Partiyaning "to'lgan" deb hisoblanadigan nishon (target) kip soni —
/// Tola uchun 220, qolgan mahsulotlar uchun 210.
const _nishonSoni = {'tola': 220, 'lint': 210, 'pux': 210, 'ulyuk': 210};

int _nishon(String mahsulotKodi) => _nishonSoni[mahsulotKodi] ?? 210;

class PartiyalarEkrani extends StatefulWidget {
  const PartiyalarEkrani({super.key});

  @override
  State<PartiyalarEkrani> createState() => _PartiyalarEkraniState();
}

class _PartiyalarEkraniState extends State<PartiyalarEkrani> {
  Sahifalangan<Partiya>? _sahifa;
  bool _yuklanmoqda = true;
  String? _xato;
  String? _holatiFiltri;
  String? _mahsulotKodiFiltri;

  final _qidiruvKontrolleri = TextEditingController();
  Timer? _qidiruvTaymer;

  @override
  void initState() {
    super.initState();
    _yuklash();
  }

  @override
  void dispose() {
    _qidiruvTaymer?.cancel();
    _qidiruvKontrolleri.dispose();
    super.dispose();
  }

  void _qidiruvOzgardi(String qiymat) {
    _qidiruvTaymer?.cancel();
    _qidiruvTaymer = Timer(const Duration(milliseconds: 500), _yuklash);
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final query = <String, dynamic>{'sahifa': 1, 'sahifa_hajmi': 100};
      if (_holatiFiltri != null) query['holati'] = _holatiFiltri;
      if (_mahsulotKodiFiltri != null) {
        query['mahsulot_kodi'] = _mahsulotKodiFiltri;
      }
      final qidiruv = _qidiruvKontrolleri.text.trim();
      if (qidiruv.isNotEmpty) query['qidiruv'] = qidiruv;
      final javob = await context.read<AppState>().api.get(
        '/partiyalar',
        query: query,
      );
      setState(
        () =>
            _sahifa = Sahifalangan.fromJson(javob, (e) => Partiya.fromJson(e)),
      );
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _yopish(Partiya p) async {
    try {
      await context.read<AppState>().api.patch('/partiyalar/${p.id}/yopish');
      _yuklash();
    } catch (e) {
      _xatoKorsat(e.toString());
    }
  }

  void _xatoKorsat(String xabar) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(xabar), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _sotishFormasiniOchish(Partiya p) async {
    final lok = context.read<AppState>().lok;
    final xaridorKontrolleri = TextEditingController();
    final dogovorRaqamiKontrolleri = TextEditingController();
    final sofVaznKontrolleri = TextEditingController();
    final uramaBilanKontrolleri = TextEditingController();
    final uramaKontrolleri = TextEditingController();
    final kondicionKontrolleri = TextEditingController();
    final sortKontrolleri = TextEditingController();

    final natija = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${lok.t("sotish")} — Partiya #${p.partiyaRaqami}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: xaridorKontrolleri,
                decoration: InputDecoration(labelText: lok.t('xaridor')),
              ),
              TextField(
                controller: dogovorRaqamiKontrolleri,
                decoration: InputDecoration(labelText: lok.t('dogovor_raqami')),
              ),
              TextField(
                controller: sortKontrolleri,
                decoration: InputDecoration(labelText: lok.t('sort')),
              ),
              TextField(
                controller: uramaBilanKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: lok.t('urama_bilan_vazn'),
                ),
              ),
              TextField(
                controller: uramaKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: lok.t('urama_vazni')),
              ),
              TextField(
                controller: sofVaznKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: lok.t('sof_vazn')),
              ),
              TextField(
                controller: kondicionKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: lok.t('kondicion_vazni'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(lok.t('bekor')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppState>().api.post(
                  '/partiyalar/${p.id}/sotish',
                  tana: {
                    'sotuv_sanasi': DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    ),
                    'xaridor': xaridorKontrolleri.text.trim(),
                    'dogovor_raqami': dogovorRaqamiKontrolleri.text.trim().isEmpty
                        ? null
                        : dogovorRaqamiKontrolleri.text.trim(),
                    'sort': sortKontrolleri.text.trim().isEmpty
                        ? null
                        : sortKontrolleri.text.trim(),
                    'urama_bilan_vazn':
                        double.tryParse(uramaBilanKontrolleri.text) ?? 0,
                    'urama_vazni': double.tryParse(uramaKontrolleri.text) ?? 0,
                    'sof_vazn': double.tryParse(sofVaznKontrolleri.text) ?? 0,
                    'kondicion_vazni': double.tryParse(
                      kondicionKontrolleri.text,
                    ),
                  },
                );
                if (context.mounted) Navigator.of(context).pop(true);
              } on ApiException catch (e) {
                _xatoKorsat(e.xabar);
              }
            },
            child: Text(lok.t('sotish')),
          ),
        ],
      ),
    );

    if (natija == true) _yuklash();
  }

  Future<void> _olchovFormasiniOchish(Partiya p) async {
    final lok = context.read<AppState>().lok;
    final sortKontrolleri = TextEditingController(text: p.sort ?? '');
    final uramaBilanKontrolleri = TextEditingController(
      text: p.uramaBilanVazn?.toString() ?? '',
    );
    final uramaKontrolleri = TextEditingController(
      text: p.uramaVazni?.toString() ?? '',
    );
    final sofVaznKontrolleri = TextEditingController(
      text: p.sofVazn?.toString() ?? '',
    );
    final kondicionKontrolleri = TextEditingController(
      text: p.kondicionVazni?.toString() ?? '',
    );

    final natija = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${lok.t("sort_ogirlik_toldirish")} — Partiya #${p.partiyaRaqami}',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sortKontrolleri,
                decoration: InputDecoration(labelText: lok.t('sort')),
              ),
              TextField(
                controller: uramaBilanKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: lok.t('urama_bilan_vazn'),
                ),
              ),
              TextField(
                controller: uramaKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: lok.t('urama_vazni')),
              ),
              TextField(
                controller: sofVaznKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: lok.t('sof_vazn')),
              ),
              TextField(
                controller: kondicionKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: lok.t('kondicion_vazni'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(lok.t('bekor')),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await context.read<AppState>().api.patch(
                  '/partiyalar/${p.id}/olchov-toldirish',
                  tana: {
                    'sort': sortKontrolleri.text.trim().isEmpty
                        ? null
                        : sortKontrolleri.text.trim(),
                    'urama_bilan_vazn':
                        double.tryParse(uramaBilanKontrolleri.text) ?? 0,
                    'urama_vazni': double.tryParse(uramaKontrolleri.text) ?? 0,
                    'sof_vazn': double.tryParse(sofVaznKontrolleri.text) ?? 0,
                    'kondicion_vazni': double.tryParse(
                      kondicionKontrolleri.text,
                    ),
                  },
                );
                if (context.mounted) Navigator.of(context).pop(true);
              } on ApiException catch (e) {
                _xatoKorsat(e.xabar);
              }
            },
            child: Text(lok.t('saqlash')),
          ),
        ],
      ),
    );

    if (natija == true) _yuklash();
  }

  void _batafsilniOchish(Partiya p, bool adminRoli) {
    partiyaBatafsilDialogniKorsat(
      context: context,
      partiya: p,
      adminRoli: adminRoli,
      onYopish: !adminRoli || p.holati != 'ochiq' ? null : () => _yopish(p),
      onSotish: !adminRoli || p.holati != 'yopiq'
          ? null
          : () => _sotishFormasiniOchish(p),
      onOlchovToldirish: adminRoli || p.holati != 'yopiq'
          ? null
          : () => _olchovFormasiniOchish(p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;
    final adminRoli = holat.foydalanuvchi?.rol == 'admin';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _filtrTugmasi(lok.t('barchasi'), null),
                  _filtrTugmasi(lok.t('ochiq'), 'ochiq'),
                  _filtrTugmasi(lok.t('yopiq'), 'yopiq'),
                  _filtrTugmasi(lok.t('sotildi'), 'sotilgan'),
                ],
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _qidiruvKontrolleri,
                  onChanged: _qidiruvOzgardi,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: lok.t('qidiruv'),
                    hintText: lok.t('partiyalar_qidiruv_maslahat'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _mahsulotTugmasi(lok.t('barchasi'), null),
              for (final kod in _nishonSoni.keys)
                _mahsulotTugmasi(lok.t(kod), kod),
            ],
          ),
          const SizedBox(height: 16),
          if (_yuklanmoqda)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null)
            Expanded(
              child: _sahifa!.items.isEmpty
                  ? Center(
                      child: Text(
                        lok.t('partiyalar_topilmadi'),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 360,
                                mainAxisExtent: 186,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                              ),
                          itemCount: _sahifa!.items.length,
                          itemBuilder: (context, i) => _partiyaKartasi(
                            _sahifa!.items[i],
                            lok,
                            adminRoli,
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _filtrTugmasi(String matn, String? qiymat) {
    final tanlanganmi = _holatiFiltri == qiymat;
    return SizedBox(
      width: 104,
      height: 36,
      child: ChoiceChip(
        label: Center(child: Text(matn, overflow: TextOverflow.ellipsis)),
        selected: tanlanganmi,
        showCheckmark: false,
        labelStyle: TextStyle(
          color: tanlanganmi ? Colors.white : null,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: kipTaroziYashil,
        onSelected: (_) {
          setState(() => _holatiFiltri = qiymat);
          _yuklash();
        },
      ),
    );
  }

  /// Mahsulot filtri — har bir mahsulot o'zining brend rangida (Statistika/
  /// Hujjatlar/Dashboard/Operator ekranlarida ishlatilgan `mahsulotRangi`
  /// bilan izchil): tanlangan — to'liq shu rang bilan to'ldirilgan,
  /// tanlanmagan — shu rang bilan chegaralangan. "Barchasi" — neytral yashil.
  Widget _mahsulotTugmasi(String matn, String? qiymat) {
    final tanlanganmi = _mahsulotKodiFiltri == qiymat;
    final rang = qiymat == null ? kipTaroziYashil : mahsulotRangi(qiymat);
    void tanlash() {
      setState(() => _mahsulotKodiFiltri = qiymat);
      _yuklash();
    }

    return SizedBox(
      width: 110,
      height: 40,
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

  Color _holatRangi(String holati) {
    switch (holati) {
      case 'ochiq':
        return kipTaroziYashil;
      case 'sotilgan':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade500;
    }
  }

  String _sana(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  Widget _partiyaKartasi(Partiya p, dynamic lok, bool adminRoli) {
    final rang = _holatRangi(p.holati);
    final holatMatni = p.holati == 'ochiq'
        ? lok.t('ochiq')
        : p.holati == 'yopiq'
        ? lok.t('yopiq')
        : lok.t('sotildi');
    final sotilganmi = p.holati == 'sotilgan';
    final nishon = _nishon(p.mahsulotKodi);
    final progress = (p.kipSoni / nishon).clamp(0.0, 1.0);

    Widget? amalTugmasi;
    if (!adminRoli) {
      if (p.holati == 'yopiq') {
        amalTugmasi = OutlinedButton(
          onPressed: () => _olchovFormasiniOchish(p),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
          child: Text(
            lok.t('sort_ogirlik_toldirish'),
            style: const TextStyle(fontSize: 12),
          ),
        );
      }
    } else if (p.holati == 'ochiq') {
      amalTugmasi = OutlinedButton(
        onPressed: () => _yopish(p),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)),
        child: Text(lok.t('yopish'), style: const TextStyle(fontSize: 12)),
      );
    } else if (p.holati == 'yopiq') {
      amalTugmasi = FilledButton(
        onPressed: () => _sotishFormasiniOchish(p),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 32)),
        child: Text(lok.t('sotish'), style: const TextStyle(fontSize: 12)),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      // Dashboard ekranidagi kabi yengil soya — mavjud global CardTheme
      // (elevation:0) ni bu kartada mahalliy ravishda ustiga yozadi,
      // boshqa ekranlarga/global temaga taʼsir qilmaydi. surfaceTintColor
      // o'chirilgan — aks holda Material3 elevation fon rangini xiralashtirib
      // yashil rangga bo'yab yuborishi mumkin edi.
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      child: InkWell(
        onTap: () => _batafsilniOchish(p, adminRoli),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: rang),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${p.mahsulotNomi} — #${p.partiyaRaqami}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: rang.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: rang.withValues(alpha: 0.45)),
                            ),
                            child: Text(
                              holatMatni,
                              style: TextStyle(
                                color: rang,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (sotilganmi) ...[
                        _malumotQatori(
                          Icons.person_outline,
                          p.xaridor?.isNotEmpty == true ? p.xaridor! : '—',
                        ),
                        const SizedBox(height: 4),
                        _malumotQatori(
                          Icons.description_outlined,
                          p.nakladnoyRaqami ?? '—',
                        ),
                        const SizedBox(height: 4),
                        _malumotQatori(
                          Icons.event_outlined,
                          p.sotuvSanasi != null ? _sana(p.sotuvSanasi!) : '—',
                        ),
                      ] else ...[
                        Text(
                          '${p.kipSoni} / $nishon ${lok.t("soni")}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 7,
                            backgroundColor: Colors.grey.shade200,
                            color: rang,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _malumotQatori(
                          Icons.event_outlined,
                          _sana(p.yaratilganVaqt),
                        ),
                      ],
                      const Spacer(),
                      if (amalTugmasi != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: amalTugmasi,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _malumotQatori(IconData ikonka, String matn) {
    return Row(
      children: [
        Icon(ikonka, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            matn,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
