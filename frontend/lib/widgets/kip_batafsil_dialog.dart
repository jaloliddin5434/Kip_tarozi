import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../i18n/strings.dart';
import '../models/kip_batafsil.dart';
import '../models/mahsulot.dart';
import '../services/kip_chop_etish.dart';
import '../state/app_state.dart';

/// Hujjatlar jadvalidagi bir qatorni bosganda kipning to'liq ma'lumoti va
/// (agar tahrirlangan/o'chirilgan bo'lsa) audit tarixini ko'rsatadi.
Future<void> kipBatafsilDialogniKorsat({required BuildContext context, required int kipId}) {
  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: _KipBatafsilIchki(kipId: kipId),
      ),
    ),
  );
}

class _KipBatafsilIchki extends StatefulWidget {
  final int kipId;

  const _KipBatafsilIchki({required this.kipId});

  @override
  State<_KipBatafsilIchki> createState() => _KipBatafsilIchkiState();
}

class _KipBatafsilIchkiState extends State<_KipBatafsilIchki> {
  late Future<KipBatafsil> _natija;

  @override
  void initState() {
    super.initState();
    _natija = _yuklash();
  }

  Future<KipBatafsil> _yuklash() {
    final holat = context.read<AppState>();
    return holat.api.get('/kiplar/${widget.kipId}').then((j) => KipBatafsil.fromJson(j));
  }

  void _qaytaYuklash() {
    setState(() {
      _natija = _yuklash();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return FutureBuilder<KipBatafsil>(
      future: _natija,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${snapshot.error}', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(lok.t('yopish')),
                ),
              ],
            ),
          );
        }
        return _KipBatafsilTarkibi(kip: snapshot.data!, lok: lok, qaytaYuklash: _qaytaYuklash);
      },
    );
  }
}

class _KipBatafsilTarkibi extends StatelessWidget {
  final KipBatafsil kip;
  final Lokalizatsiya lok;
  final VoidCallback qaytaYuklash;

  const _KipBatafsilTarkibi({required this.kip, required this.lok, required this.qaytaYuklash});

  String _holatiMatni() {
    switch (kip.holati) {
      case 'aktiv':
        return lok.t('holati_aktiv');
      case 'bekor_qilingan':
        return lok.t('holati_bekor_qilingan');
      case 'tahrirlangan':
        return lok.t('holati_tahrirlangan');
      default:
        return kip.holati;
    }
  }

  String _amalMatni(String amal) {
    switch (amal) {
      case 'yaratildi':
        return lok.t('yaratildi');
      case 'tahrirlandi':
        return lok.t('tahrirlandi');
      case 'ochirildi':
        return lok.t('ochirildi');
      default:
        return amal;
    }
  }

  String _vaqtMatni(DateTime vaqt) => vaqt.toLocal().toString().substring(0, 16);

  @override
  Widget build(BuildContext context) {
    final adminRoli = context.watch<AppState>().foydalanuvchi?.rol == 'admin';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${lok.t("kip_batafsil")} — #${kip.kipRaqami}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (adminRoli)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: lok.t('tahrirlash'),
                  onPressed: () async {
                    final saqlandi = await _tahrirlashFormasiniOchish(context, kip);
                    if (saqlandi == true) qaytaYuklash();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: lok.t('chop_etish'),
                onPressed: () => kipniChopEtish(kip, lok),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
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
                _qator(lok.t('mahsulot'), kip.mahsulotNomi),
                _qator(lok.t('partiya'), '#${kip.partiyaRaqami}'),
                _qator(lok.t('kip_qisqa'), '${kip.kipRaqami}'),
                _qator(lok.t('ogirlik'), '${kip.ogirlik.toStringAsFixed(1)} ${lok.t("kg")}'),
                _qator(lok.t('smena'), kip.smena),
                _qator(lok.t('operator'), kip.operatorIsm),
                _qator(lok.t('vaqt'), _vaqtMatni(kip.vaqt)),
                _qator(lok.t('holati'), _holatiMatni()),
                const SizedBox(height: 12),
                Text(lok.t('surat'), style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 6),
                _suratKorinishi(kip.suratYoli),
                if (kip.auditLog.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(lok.t('audit_tarixi'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...kip.auditLog.map(_auditKartasi),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _qator(String sarlavha, String qiymat) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(sarlavha, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(qiymat)),
        ],
      ),
    );
  }

  Widget _suratKorinishi(String? suratYoli) {
    if (suratYoli == null || suratYoli.isEmpty) {
      return _suratPlaceholder(Icons.image_not_supported_outlined, lok.t('surat_yoq'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        suratYoli,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            height: 180,
            child: Container(
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            _suratPlaceholder(Icons.broken_image_outlined, lok.t('surat_yuklanmadi')),
      ),
    );
  }

  Widget _suratPlaceholder(IconData ikonka, String matn) {
    return Container(
      height: 140,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikonka, color: Colors.grey.shade400, size: 32),
          const SizedBox(height: 6),
          Text(matn, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _auditKartasi(AuditLogYozuvi yozuv) {
    final ozgargan = {...?yozuv.yangiQiymat}.keys.toList();
    return Card(
      color: Colors.orange.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_amalMatni(yozuv.amal)} — ${yozuv.foydalanuvchiIsm} — ${_vaqtMatni(yozuv.vaqt)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('${lok.t("sabab")}: ${yozuv.sabab}'),
            for (final kalit in ozgargan)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$kalit: ${yozuv.eskiQiymat?[kalit] ?? "—"} → ${yozuv.yangiQiymat?[kalit]}'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Admin uchun kipning og'irligi, mahsuloti va partiyasini tuzatish formasi.
/// Muvaffaqiyatli saqlansa `true` qaytaradi.
Future<bool?> _tahrirlashFormasiniOchish(BuildContext context, KipBatafsil kip) async {
  final holat = context.read<AppState>();
  final lok = holat.lok;

  List<Mahsulot> mahsulotlar;
  try {
    final javob = await holat.api.get('/mahsulotlar');
    mahsulotlar = (javob as List).map((e) => Mahsulot.fromJson(e)).toList();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    }
    return null;
  }

  final ogirlikKontrolleri = TextEditingController(text: kip.ogirlik.toStringAsFixed(1));
  final partiyaRaqamiKontrolleri = TextEditingController(text: '${kip.partiyaRaqami}');
  final sababKontrolleri = TextEditingController();
  String tanlanganMahsulotKodi = kip.mahsulotKodi;
  String? xato;

  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text('${lok.t("tahrirlash")} — #${kip.kipRaqami}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: tanlanganMahsulotKodi,
                decoration: InputDecoration(labelText: lok.t('mahsulot')),
                items: mahsulotlar.map((m) => DropdownMenuItem(value: m.kod, child: Text(m.nomi))).toList(),
                onChanged: (v) => setState(() => tanlanganMahsulotKodi = v ?? tanlanganMahsulotKodi),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: partiyaRaqamiKontrolleri,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: lok.t('partiya_raqami')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ogirlikKontrolleri,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: lok.t('ogirlik')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sababKontrolleri,
                decoration: InputDecoration(labelText: lok.t('sabab')),
              ),
              if (xato != null) ...[
                const SizedBox(height: 12),
                Text(xato!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(lok.t('bekor'))),
          FilledButton(
            onPressed: () async {
              final ogirlik = double.tryParse(ogirlikKontrolleri.text.trim().replaceAll(',', '.'));
              final partiyaRaqami = int.tryParse(partiyaRaqamiKontrolleri.text.trim());
              final sabab = sababKontrolleri.text.trim();
              if (ogirlik == null || partiyaRaqami == null || sabab.isEmpty) {
                setState(() => xato = lok.t('maydonlar_toldirilmagan'));
                return;
              }
              try {
                await holat.api.patch(
                  '/kiplar/${kip.id}',
                  tana: {
                    'ogirlik': ogirlik,
                    'mahsulot_kodi': tanlanganMahsulotKodi,
                    'partiya_raqami': partiyaRaqami,
                    'sabab': sabab,
                  },
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop(true);
              } on ApiException catch (e) {
                setState(() => xato = e.xabar);
              }
            },
            child: Text(lok.t('saqlash')),
          ),
        ],
      ),
    ),
  );
}
