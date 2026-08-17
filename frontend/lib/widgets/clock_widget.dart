import 'dart:async';
import 'package:flutter/material.dart';

class SoatWidget extends StatefulWidget {
  final TextStyle? style;
  const SoatWidget({super.key, this.style});

  @override
  State<SoatWidget> createState() => _SoatWidgetState();
}

class _SoatWidgetState extends State<SoatWidget> {
  late Timer _timer;
  DateTime _hozir = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _hozir = DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _ikkiXonali(int son) => son.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final matn =
        '${_ikkiXonali(_hozir.hour)}:${_ikkiXonali(_hozir.minute)}:${_ikkiXonali(_hozir.second)}  ${_ikkiXonali(_hozir.day)}.${_ikkiXonali(_hozir.month)}.${_hozir.year}';
    return Text(matn, style: widget.style);
  }
}
