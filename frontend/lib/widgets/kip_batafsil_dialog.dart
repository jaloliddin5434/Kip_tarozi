import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../models/kip_batafsil.dart';
import '../services/kip_chop_etish.dart';
import '../state/app_state.dart';

/// Hujjatlar jadvalidagi bir qatorni bosganda kipning to'liq ma'lumoti va
/// (agar tahrirlangan/o'chirilgan bo'lsa) audit tarixini ko'rsatadi.
Future<void> kipBatafsilDialogniKorsat({required BuildContext context, required int kipId}) {
  final holat = context.read<AppState>();
  final lok = holat.lok;
  final natija = holat.api.get('/kiplar/$kipId').then((j) => KipBatafsil.fromJson(j));

  return showDialog(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: FutureBuilder<KipBatafsil>(
          future: natija,
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
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(lok.t('yopish')),
                    ),
                  ],
                ),
              );
            }
            return _KipBatafsilTarkibi(kip: snapshot.data!, lok: lok);
          },
        ),
      ),
    ),
  );
}

class _KipBatafsilTarkibi extends StatelessWidget {
  final KipBatafsil kip;
  final Lokalizatsiya lok;

  const _KipBatafsilTarkibi({required this.kip, required this.lok});

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
                if (kip.suratYoli != null) _qator(lok.t('surat'), kip.suratYoli!),
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
