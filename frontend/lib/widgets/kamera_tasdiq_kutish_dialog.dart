import 'dart:async';

import 'package:flutter/material.dart';
import '../i18n/strings.dart';

/// "Admin ruxsati kutilmoqda" — kamera surat ololmaganda operatorni TO'LIQ
/// bloklaydigan dialog. Orqaga tugmasi / tashqariga bosish ishlamaydi.
/// [boshlanishVaqti] — so'rov QACHON yaratilgani (operator ilovani qayta
/// ochsa ham hisoblagich shu paytdan davom etsin uchun) — dialog ichida
/// har soniyada yangilanadigan "necha vaqtdan beri kutilmoqda" hisoblagichini
/// ko'rsatish uchun ishlatiladi. Bloklovchi mexanizmning o'zi (faqat [tugash]
/// Future bajarilganda yopiladi) o'zgarmaydi — bu FAQAT vizual qo'shimcha.
/// [tugash] Future bajarilganda dialog o'zini yopadi (operator ekrani polling
/// qilib, tasdiqlangan/rad etilgan holatda uni bajaradi).
Future<void> kameraTasdiqKutishDialogniKorsat({
  required BuildContext context,
  required Lokalizatsiya lok,
  required DateTime boshlanishVaqti,
  required Future<void> tugash,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      tugash.whenComplete(() {
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      });
      return PopScope(
        canPop: false,
        child: _KutishDialogTarkibi(lok: lok, boshlanishVaqti: boshlanishVaqti),
      );
    },
  );
}

class _KutishDialogTarkibi extends StatefulWidget {
  final Lokalizatsiya lok;
  final DateTime boshlanishVaqti;

  const _KutishDialogTarkibi({required this.lok, required this.boshlanishVaqti});

  @override
  State<_KutishDialogTarkibi> createState() => _KutishDialogTarkibiState();
}

class _KutishDialogTarkibiState extends State<_KutishDialogTarkibi> {
  Timer? _soniyalikTaymer;
  late Duration _otganVaqt;

  @override
  void initState() {
    super.initState();
    _otganVaqtniYangilash();
    _soniyalikTaymer = Timer.periodic(const Duration(seconds: 1), (_) => _otganVaqtniYangilash());
  }

  @override
  void dispose() {
    _soniyalikTaymer?.cancel();
    super.dispose();
  }

  void _otganVaqtniYangilash() {
    final yangi = DateTime.now().difference(widget.boshlanishVaqti);
    // Manfiy bo'lib qolmasin (masalan server/qurilma soati bir necha soniya
    // farq qilsa) — 0 dan boshlanadi.
    setState(() => _otganVaqt = yangi.isNegative ? Duration.zero : yangi);
  }

  String _hisoblagichMatni() {
    final daqiqa = _otganVaqt.inMinutes;
    final soniya = _otganVaqt.inSeconds % 60;
    final kalit = daqiqa > 0 ? 'kamera_tasdigi_kutish_daqiqali' : 'kamera_tasdigi_kutish_soniyali';
    return widget.lok
        .t(kalit)
        .replaceFirst('{daq}', '$daqiqa')
        .replaceFirst('{son}', '$soniya');
  }

  @override
  Widget build(BuildContext context) {
    final lok = widget.lok;
    return AlertDialog(
      icon: const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 48),
      title: Text(lok.t('kamera_tasdigi_kutilmoqda_sarlavha'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(lok.t('kamera_tasdigi_kutilmoqda_matn'), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _hisoblagichMatni(),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
