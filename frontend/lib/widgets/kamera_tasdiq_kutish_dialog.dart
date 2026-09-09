import 'package:flutter/material.dart';
import '../i18n/strings.dart';

/// "Admin ruxsati kutilmoqda" — kamera surat ololmaganda operatorni TO'LIQ
/// bloklaydigan dialog. Orqaga tugmasi / tashqariga bosish ishlamaydi.
/// [tugash] Future bajarilganda dialog o'zini yopadi (operator ekrani polling
/// qilib, tasdiqlangan/rad etilgan holatda uni bajaradi).
Future<void> kameraTasdiqKutishDialogniKorsat({
  required BuildContext context,
  required Lokalizatsiya lok,
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
        child: AlertDialog(
          icon: const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 48),
          title: Text(lok.t('kamera_tasdigi_kutilmoqda_sarlavha'), textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(lok.t('kamera_tasdigi_kutilmoqda_matn'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    },
  );
}
