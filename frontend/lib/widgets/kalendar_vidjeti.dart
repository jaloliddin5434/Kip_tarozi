import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Statistika va Hujjatlar ekranlarida ishlatiladigan qayta foydalaniladigan
/// oy-kalendar vidjeti. Bir kun bosilganda [onKunTanlash] chaqiriladi;
/// bugungi kun ramka bilan, [tanlanganKun] esa yashil fon bilan belgilanadi.
class KalendarVidjeti extends StatefulWidget {
  final DateTime? tanlanganKun;
  final ValueChanged<DateTime> onKunTanlash;

  const KalendarVidjeti({super.key, required this.tanlanganKun, required this.onKunTanlash});

  @override
  State<KalendarVidjeti> createState() => _KalendarVidjetiState();
}

class _KalendarVidjetiState extends State<KalendarVidjeti> {
  late DateTime _oy;

  @override
  void initState() {
    super.initState();
    final asos = widget.tanlanganKun ?? DateTime.now();
    _oy = DateTime(asos.year, asos.month);
  }

  @override
  void didUpdateWidget(covariant KalendarVidjeti oldWidget) {
    super.didUpdateWidget(oldWidget);
    final kun = widget.tanlanganKun;
    if (kun != null && (kun.year != _oy.year || kun.month != _oy.month)) {
      setState(() => _oy = DateTime(kun.year, kun.month));
    }
  }

  bool _birXilKunmi(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;
    final oyBoshi = DateTime(_oy.year, _oy.month, 1);
    final oyOxiri = DateTime(_oy.year, _oy.month + 1, 0);
    final boshlanishOffset = oyBoshi.weekday - 1;
    final kunlarSoni = oyOxiri.day;
    final qatorSoni = ((boshlanishOffset + kunlarSoni) / 7).ceil();
    final bugun = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: lok.t('oldingi_oy'),
                onPressed: () => setState(() => _oy = DateTime(_oy.year, _oy.month - 1)),
              ),
              Text(
                '${lok.t("oy_${_oy.month}")} ${_oy.year}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: lok.t('keyingi_oy'),
                onPressed: () => setState(() => _oy = DateTime(_oy.year, _oy.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var h = 1; h <= 7; h++)
                Expanded(
                  child: Center(
                    child: Text(lok.t('hafta_$h'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var q = 0; q < qatorSoni; q++)
            Row(children: [for (var d = 0; d < 7; d++) _kunKatakchasi(q * 7 + d, boshlanishOffset, kunlarSoni, bugun)]),
        ],
      ),
    );
  }

  Widget _kunKatakchasi(int index, int offset, int kunlarSoni, DateTime bugun) {
    final kunRaqami = index - offset + 1;
    if (kunRaqami < 1 || kunRaqami > kunlarSoni) {
      return const Expanded(child: SizedBox(height: 36));
    }
    final kun = DateTime(_oy.year, _oy.month, kunRaqami);
    final bugunmi = _birXilKunmi(kun, bugun);
    final tanlanganmi = widget.tanlanganKun != null && _birXilKunmi(kun, widget.tanlanganKun!);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => widget.onKunTanlash(kun),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tanlanganmi ? kipTaroziYashil : null,
              border: bugunmi && !tanlanganmi ? Border.all(color: kipTaroziYashil) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$kunRaqami',
              style: TextStyle(
                color: tanlanganmi ? Colors.white : null,
                fontWeight: bugunmi ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
