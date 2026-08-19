import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../i18n/strings.dart';
import '../models/hujjat.dart';
import '../models/partiya.dart';
import '../services/fayl_yuklab_olish.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Partiyalar ekranidagi bir kartani bosganda partiyaning to'liq ma'lumoti
/// va unga tegishli kiplar ro'yxatini ko'rsatadi.
Future<void> partiyaBatafsilDialogniKorsat({
  required BuildContext context,
  required Partiya partiya,
  required bool adminRoli,
  Future<void> Function()? onYopish,
  Future<void> Function()? onSotish,
  Future<void> Function()? onOlchovToldirish,
}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: _PartiyaBatafsilIchki(
          partiya: partiya,
          adminRoli: adminRoli,
          onYopish: onYopish,
          onSotish: onSotish,
          onOlchovToldirish: onOlchovToldirish,
        ),
      ),
    ),
  );
}

class _PartiyaBatafsilIchki extends StatefulWidget {
  final Partiya partiya;
  final bool adminRoli;
  final Future<void> Function()? onYopish;
  final Future<void> Function()? onSotish;
  final Future<void> Function()? onOlchovToldirish;

  const _PartiyaBatafsilIchki({
    required this.partiya,
    required this.adminRoli,
    this.onYopish,
    this.onSotish,
    this.onOlchovToldirish,
  });

  @override
  State<_PartiyaBatafsilIchki> createState() => _PartiyaBatafsilIchkiState();
}

class _PartiyaBatafsilIchkiState extends State<_PartiyaBatafsilIchki> {
  late Future<List<HujjatKip>> _kiplarNatija;
  bool _amalBajarilmoqda = false;
  bool _nakladnoyYuklanmoqda = false;

  @override
  void initState() {
    super.initState();
    _kiplarNatija = _kiplarniYuklash();
  }

  Future<List<HujjatKip>> _kiplarniYuklash() async {
    final holat = context.read<AppState>();
    final javob = await holat.api.get(
      '/hujjatlar/kiplar',
      query: {
        'mahsulot_kodi': widget.partiya.mahsulotKodi,
        'partiya_raqami': widget.partiya.partiyaRaqami,
        'sahifa_hajmi': 500,
      },
    );
    final sahifa = Sahifalangan.fromJson(javob, (e) => HujjatKip.fromJson(e));
    return sahifa.items;
  }

  Future<void> _amalniBajarish(Future<void> Function() amal) async {
    setState(() => _amalBajarilmoqda = true);
    try {
      await amal();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _nakladnoyniYuklab() async {
    final holat = context.read<AppState>();
    final lok = holat.lok;
    setState(() => _nakladnoyYuklanmoqda = true);
    try {
      final baytlar = await holat.api.getBaytlar(
        '/partiyalar/${widget.partiya.id}/nakladnoy',
      );
      faylniSaqlash(baytlar, '${widget.partiya.nakladnoyRaqami}.pdf');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(lok.t('fayl_yuklab_olindi'))));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.xabar),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _nakladnoyYuklanmoqda = false);
    }
  }

  String _sana(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _vaqtMatni(DateTime vaqt) =>
      vaqt.toLocal().toString().substring(0, 16);

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

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;
    final p = widget.partiya;
    final rang = _holatRangi(p.holati);
    final holatMatni = p.holati == 'ochiq'
        ? lok.t('ochiq')
        : p.holati == 'yopiq'
        ? lok.t('yopiq')
        : lok.t('sotildi');
    final sotilganmi = p.holati == 'sotilgan';
    final yopiqYokiSotilgan = p.holati == 'yopiq' || sotilganmi;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${lok.t("partiya_batafsil")} — ${p.mahsulotNomi} #${p.partiyaRaqami}',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: rang.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  holatMatni,
                  style: TextStyle(
                    color: rang,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _qator(lok.t('mahsulot'), p.mahsulotNomi),
                _qator(lok.t('partiya_raqami'), '#${p.partiyaRaqami}'),
                _qator(lok.t('holati'), holatMatni),
                _qator(lok.t('kip_soni'), '${p.kipSoni}'),
                _qator(
                  lok.t('jami_ogirlik'),
                  '${p.jamiKg.toStringAsFixed(1)} ${lok.t("kg")}',
                ),
                _qator(lok.t('yaratilgan_sana'), _sana(p.yaratilganVaqt)),
                if (yopiqYokiSotilgan && p.yopilganVaqt != null)
                  _qator(lok.t('yopilgan_sana'), _sana(p.yopilganVaqt!)),
                if (sotilganmi) ...[
                  if (p.sotuvSanasi != null)
                    _qator(lok.t('sotilgan_sana'), _sana(p.sotuvSanasi!)),
                  _qator(
                    lok.t('xaridor'),
                    p.xaridor?.isNotEmpty == true ? p.xaridor! : '—',
                  ),
                  _qator(
                    lok.t('dogovor_raqami'),
                    p.dogovorRaqami?.isNotEmpty == true
                        ? p.dogovorRaqami!
                        : '—',
                  ),
                  _qator(
                    lok.t('sort'),
                    p.sort?.isNotEmpty == true ? p.sort! : '—',
                  ),
                  _qator(
                    lok.t('urama_bilan_vazn'),
                    p.uramaBilanVazn != null
                        ? '${p.uramaBilanVazn!.toStringAsFixed(1)} ${lok.t("kg")}'
                        : '—',
                  ),
                  _qator(
                    lok.t('urama_vazni'),
                    p.uramaVazni != null
                        ? '${p.uramaVazni!.toStringAsFixed(1)} ${lok.t("kg")}'
                        : '—',
                  ),
                  _qator(
                    lok.t('sof_vazn'),
                    p.sofVazn != null
                        ? '${p.sofVazn!.toStringAsFixed(1)} ${lok.t("kg")}'
                        : '—',
                  ),
                  _qator(
                    lok.t('kondicion_vazni'),
                    p.kondicionVazni != null
                        ? '${p.kondicionVazni!.toStringAsFixed(1)} ${lok.t("kg")}'
                        : '—',
                  ),
                  _qator(lok.t('nakladnoy'), p.nakladnoyRaqami ?? '—'),
                ],
                const SizedBox(height: 16),
                Text(
                  lok.t('partiyadagi_kiplar'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SizedBox(height: 220, child: _kiplarRoyxati(lok)),
              ],
            ),
          ),
        ),
        if (_amalTugmasi(lok) != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerRight,
              child: _amalTugmasi(lok),
            ),
          ),
        ],
      ],
    );
  }

  Widget? _amalTugmasi(Lokalizatsiya lok) {
    final p = widget.partiya;

    if (p.holati == 'sotilgan') {
      if (p.nakladnoyRaqami == null) return null;
      return OutlinedButton.icon(
        onPressed: _nakladnoyYuklanmoqda ? null : _nakladnoyniYuklab,
        icon: _nakladnoyYuklanmoqda
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.picture_as_pdf_outlined, size: 18),
        label: Text(lok.t('nakladnoy_yuklab_olish')),
      );
    }

    if (_amalBajarilmoqda) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!widget.adminRoli) {
      if (p.holati == 'yopiq' && widget.onOlchovToldirish != null) {
        return OutlinedButton(
          onPressed: () => _amalniBajarish(widget.onOlchovToldirish!),
          child: Text(lok.t('sort_ogirlik_toldirish')),
        );
      }
      return null;
    }
    if (p.holati == 'ochiq' && widget.onYopish != null) {
      return OutlinedButton(
        onPressed: () => _amalniBajarish(widget.onYopish!),
        child: Text(lok.t('yopish')),
      );
    }
    if (p.holati == 'yopiq' && widget.onSotish != null) {
      return FilledButton(
        onPressed: () => _amalniBajarish(widget.onSotish!),
        child: Text(lok.t('sotish')),
      );
    }
    return null;
  }

  Widget _kiplarRoyxati(Lokalizatsiya lok) {
    return FutureBuilder<List<HujjatKip>>(
      future: _kiplarNatija,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final kiplar = snapshot.data!;
        if (kiplar.isEmpty) {
          return Center(
            child: Text(
              lok.t('kiplar_topilmadi'),
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }
        return ListView.separated(
          itemCount: kiplar.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _kipQatori(kiplar[i], lok),
        );
      },
    );
  }

  Widget _kipQatori(HujjatKip kip, Lokalizatsiya lok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '#${kip.kipRaqami}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text('${kip.ogirlik.toStringAsFixed(1)} ${lok.t("kg")}'),
          ),
          Expanded(
            child: Text(kip.operatorIsm, overflow: TextOverflow.ellipsis),
          ),
          Text(
            _vaqtMatni(kip.vaqt),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _qator(String sarlavha, String qiymat) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(sarlavha, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(qiymat)),
        ],
      ),
    );
  }
}
