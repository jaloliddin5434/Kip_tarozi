import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../models/hujjat.dart';
import '../../models/partiya.dart';
import '../../state/app_state.dart';

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
      final query = <String, dynamic>{'sahifa': 1, 'sahifa_hajmi': 100};
      if (_holatiFiltri != null) query['holati'] = _holatiFiltri;
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
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(lok.t('ochiq')),
                selected: _holatiFiltri == 'ochiq',
                onSelected: (_) {
                  setState(() => _holatiFiltri = 'ochiq');
                  _yuklash();
                },
              ),
              ChoiceChip(
                label: Text(lok.t('yopiq')),
                selected: _holatiFiltri == 'yopiq',
                onSelected: (_) {
                  setState(() => _holatiFiltri = 'yopiq');
                  _yuklash();
                },
              ),
              ChoiceChip(
                label: Text(lok.t('sotildi')),
                selected: _holatiFiltri == 'sotilgan',
                onSelected: (_) {
                  setState(() => _holatiFiltri = 'sotilgan');
                  _yuklash();
                },
              ),
              ActionChip(
                label: Text(lok.t('tozalash')),
                onPressed: () {
                  setState(() => _holatiFiltri = null);
                  _yuklash();
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_yuklanmoqda)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null && _sahifa != null)
            Expanded(
              child: ListView(
                children: _sahifa!.items
                    .map((p) => _partiyaKartasi(p, lok, adminRoli))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _partiyaKartasi(Partiya p, dynamic lok, bool adminRoli) {
    final sotilganmi = p.holati == 'sotilgan';
    final rang = sotilganmi ? Colors.red : Colors.green;
    return Card(
      color: rang.withValues(alpha: 0.06),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rang,
          child: Text(
            '#${p.partiyaRaqami}',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
        title: Text('${p.mahsulotNomi} — Partiya #${p.partiyaRaqami}'),
        subtitle: Text(
          '${p.kipSoni} ${lok.t("soni")} · ${p.jamiKg.toStringAsFixed(1)} kg · ${lok.t(p.holati == "ochiq"
              ? "ochiq"
              : p.holati == "yopiq"
              ? "yopiq"
              : "sotildi")}'
          '${p.sort != null ? " · ${lok.t('sort')}: ${p.sort}" : ""}'
          '${p.xaridor != null ? " · ${p.xaridor}" : ""}${p.nakladnoyRaqami != null ? " · ${p.nakladnoyRaqami}" : ""}',
        ),
        trailing: !adminRoli
            ? (p.holati == 'yopiq'
                  ? OutlinedButton(
                      onPressed: () => _olchovFormasiniOchish(p),
                      child: Text(lok.t('sort_ogirlik_toldirish')),
                    )
                  : null)
            : p.holati == 'ochiq'
            ? OutlinedButton(
                onPressed: () => _yopish(p),
                child: Text(lok.t('yopish')),
              )
            : p.holati == 'yopiq'
            ? FilledButton(
                onPressed: () => _sotishFormasiniOchish(p),
                child: Text(lok.t('sotish')),
              )
            : null,
      ),
    );
  }
}
