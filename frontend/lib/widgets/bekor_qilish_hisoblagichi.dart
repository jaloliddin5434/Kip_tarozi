import 'dart:async';
import 'package:flutter/material.dart';

/// Kip saqlangandan keyin ~30s davomida ko'rinadigan tezkor "Bekor qilish"
/// tugmasi — hisoblagich bilan, muddat tugagach o'zi yo'qoladi.
class BekorQilishHisoblagichi extends StatefulWidget {
  final int muddatSoniya;
  final String matn;
  final Future<void> Function() onBekorQilish;
  final VoidCallback onMuddatTugadi;

  const BekorQilishHisoblagichi({
    super.key,
    required this.muddatSoniya,
    required this.matn,
    required this.onBekorQilish,
    required this.onMuddatTugadi,
  });

  @override
  State<BekorQilishHisoblagichi> createState() => _BekorQilishHisoblagichiState();
}

class _BekorQilishHisoblagichiState extends State<BekorQilishHisoblagichi> {
  late int _qolgan;
  late Timer _timer;
  bool _yuborilmoqda = false;

  @override
  void initState() {
    super.initState();
    _qolgan = widget.muddatSoniya;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _qolgan--);
      if (_qolgan <= 0) {
        _timer.cancel();
        widget.onMuddatTugadi();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _yuborilmoqda
          ? null
          : () async {
              setState(() => _yuborilmoqda = true);
              await widget.onBekorQilish();
            },
      icon: const Icon(Icons.undo),
      label: Text('${widget.matn} ($_qolgan s)'),
      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700, side: BorderSide(color: Colors.red.shade300)),
    );
  }
}
