import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/smena_holati.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'kalendar_vidjeti.dart';

/// Operator ekranidagi "Kalendar" tugmasi bosilganda ochiladigan popover —
/// kalendardan bir kun tanlansa, operatorning O'Z SMENASI bo'yicha o'sha
/// kundagi jamlanma (jami soni + mahsulot bo'yicha soni/kg) ko'rsatiladi.
/// Ma'lumot GET /kiplar/smena/kunlik-jamlanma orqali olinadi (operatorga
/// xos, faqat o'z smenasi bilan cheklangan endpoint).
Future<void> smenaKalendarDialogniKorsat(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _SmenaKalendarDialogi());
}

class _SmenaKalendarDialogi extends StatefulWidget {
  const _SmenaKalendarDialogi();

  @override
  State<_SmenaKalendarDialogi> createState() => _SmenaKalendarDialogiState();
}

class _SmenaKalendarDialogiState extends State<_SmenaKalendarDialogi> {
  late DateTime _tanlanganKun;
  bool _yuklanmoqda = false;
  String? _xato;
  SmenaHolati? _natija;

  @override
  void initState() {
    super.initState();
    _tanlanganKun = DateTime.now();
    _kunniYuklash(_tanlanganKun);
  }

  String _isoSana(DateTime kun) {
    String ikki(int s) => s.toString().padLeft(2, '0');
    return '${kun.year}-${ikki(kun.month)}-${ikki(kun.day)}';
  }

  Future<void> _kunniYuklash(DateTime kun) async {
    setState(() {
      _tanlanganKun = kun;
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final javob = await context.read<AppState>().api.get(
            '/kiplar/smena/kunlik-jamlanma',
            query: {'sana': _isoSana(kun)},
          );
      if (!mounted) return;
      setState(() => _natija = SmenaHolati.fromJson(javob));
    } catch (e) {
      if (!mounted) return;
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(lok.t('kalendar'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 340,
                    child: KalendarVidjeti(tanlanganKun: _tanlanganKun, onKunTanlash: _kunniYuklash),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: _kunNatijasi(lok)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kunNatijasi(dynamic lok) {
    if (_yuklanmoqda) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_xato != null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Text(_xato!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ),
      );
    }
    final natija = _natija;
    if (natija == null) return const SizedBox(height: 260);

    final jamiSoni = natija.mahsulotlar.fold<int>(0, (j, m) => j + m.soni);
    final jamiKg = natija.mahsulotlar.fold<double>(0, (j, m) => j + m.jamiKg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${lok.t("sana")}: ${_isoSana(_tanlanganKun)}  —  ${lok.t("smena")} ${natija.smena}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(lok.t('kun_natijasi'), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 12),
        if (natija.mahsulotlar.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(lok.t('malumot_yoq'), style: TextStyle(color: Colors.grey.shade500)),
          )
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFEAF6F1), Color(0xFFF5FAF8)]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kipTaroziYashil.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${lok.t("jami")}: $jamiSoni ${lok.t("soni")}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: kipTaroziYashil),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${jamiKg.toStringAsFixed(1)} ${lok.t("kg")}', style: const TextStyle(fontWeight: FontWeight.bold, color: kipTaroziYashil)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...natija.mahsulotlar.map((m) {
            final rang = mahsulotRangi(m.mahsulotKodi);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: rang.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rang, width: 1.2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(m.mahsulotNomi, style: TextStyle(fontWeight: FontWeight.bold, color: rang)),
                  ),
                  Text('${m.soni} ${lok.t("soni")}', style: TextStyle(color: rang, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${m.jamiKg.toStringAsFixed(1)} ${lok.t("kg")}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
