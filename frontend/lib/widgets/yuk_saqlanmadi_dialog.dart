import 'package:flutter/material.dart';
import '../i18n/strings.dart';

/// "Yuk saqlanmadi" ogohlantirishi — operator "Tushundim" bosmaguncha
/// yopilmaydi (orqaga tugmasi ham ishlamaydi), boshqa amalni bloklaydi.
Future<void> yukSaqlanmadiDialogniKorsat({
  required BuildContext context,
  required Lokalizatsiya lok,
  required Future<void> Function() onTushundim,
}) {
  bool yuborilmoqda = false;
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
            title: Text(lok.t('yuk_saqlanmadi_sarlavha'), textAlign: TextAlign.center),
            content: Text(lok.t('yuk_saqlanmadi_matn'), textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: yuborilmoqda
                    ? null
                    : () async {
                        setState(() => yuborilmoqda = true);
                        await onTushundim();
                        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                      },
                child: Text(lok.t('tushundim')),
              ),
            ],
          ),
        ),
      );
    },
  );
}
