import 'dart:async';
import 'package:flutter/material.dart';

/// Kip saqlangandan keyin ~30s davomida ko'rinadigan tezkor "Bekor qilish"
/// boshqaruvi — doiraviy progress-halqa bilan, muddat tugagach o'zi yo'qoladi.
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

  Future<void> _bosildi() async {
    if (_yuborilmoqda) return;
    setState(() => _yuborilmoqda = true);
    await widget.onBekorQilish();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _qolgan / widget.muddatSoniya;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: progress.clamp(0, 1),
                  strokeWidth: 5,
                  color: Colors.red.shade400,
                  backgroundColor: Colors.red.shade100,
                ),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _yuborilmoqda ? null : _bosildi,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: _yuborilmoqda
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red.shade700),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.undo, color: Colors.red.shade700, size: 22),
                              Text(
                                '$_qolgan s',
                                style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.matn, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
      ],
    );
  }
}
