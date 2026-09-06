import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';

class _SozlamaMaydoni {
  final String kalit;
  final String labelKaliti;
  final String? tavsifKaliti;
  final bool maxfiy;

  const _SozlamaMaydoni({required this.kalit, required this.labelKaliti, this.tavsifKaliti, this.maxfiy = false});
}

/// Backend kodida (app/services/telegram.py) haqiqatan ishlatiladigan
/// sozlama kalitlari. `moliyaviy_parol_hash` (moliyaviy bo'lim maxfiy
/// parolining hash'i) va `agent_oxirgi_holat` (stansiya agentining avtomatik
/// yozadigan holat ma'lumoti) qasddan bu ro'yxatga kiritilmagan — ular admin
/// tomonidan qo'lda tahrirlanadigan sozlama emas.
const _bolimlar = [
  (
    sarlavhaKaliti: 'telegram_xatolik_bolimi',
    maydonlar: [
      _SozlamaMaydoni(
        kalit: 'telegram_xatolik_bot_token',
        labelKaliti: 'telegram_xatolik_bot_token',
        tavsifKaliti: 'telegram_xatolik_tavsif',
        maxfiy: true,
      ),
      _SozlamaMaydoni(kalit: 'telegram_xatolik_chat_id', labelKaliti: 'telegram_xatolik_chat_id'),
    ],
  ),
  (
    sarlavhaKaliti: 'telegram_statistika_bolimi',
    maydonlar: [
      _SozlamaMaydoni(
        kalit: 'telegram_statistika_bot_token',
        labelKaliti: 'telegram_statistika_bot_token',
        tavsifKaliti: 'telegram_statistika_tavsif',
        maxfiy: true,
      ),
      _SozlamaMaydoni(kalit: 'telegram_statistika_chat_id', labelKaliti: 'telegram_statistika_chat_id'),
    ],
  ),
];

const _yashiriladiganKalitlar = {'moliyaviy_parol_hash', 'agent_oxirgi_holat'};

class SozlamalarEkrani extends StatefulWidget {
  const SozlamalarEkrani({super.key});

  @override
  State<SozlamalarEkrani> createState() => _SozlamalarEkraniState();
}

class _SozlamalarEkraniState extends State<SozlamalarEkrani> {
  bool _yuklanmoqda = true;
  String? _xato;

  final Map<String, TextEditingController> _kontrollerlar = {};
  final Map<String, bool> _matnKorinadi = {};
  final Map<String, bool> _saqlanmoqda = {};
  final List<String> _qoshimchaKalitlar = [];

  @override
  void initState() {
    super.initState();
    for (final bolim in _bolimlar) {
      for (final maydon in bolim.maydonlar) {
        _kontrollerlar[maydon.kalit] = TextEditingController();
        _matnKorinadi[maydon.kalit] = false;
      }
    }
    _yuklash();
  }

  @override
  void dispose() {
    for (final kontroller in _kontrollerlar.values) {
      kontroller.dispose();
    }
    super.dispose();
  }

  Future<void> _yuklash() async {
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      final javob = await context.read<AppState>().api.get('/sozlamalar') as List;
      // Javob kelguncha ekran dispose bo'lgan bo'lishi mumkin — bunday holda
      // pastdagi tsikl allaqachon dispose qilingan TextEditingController'larga
      // yozishga urinib qolmasligi uchun darhol to'xtaymiz.
      if (!mounted) return;
      final malumKalitlar = _bolimlar.expand((b) => b.maydonlar).map((m) => m.kalit).toSet();
      _qoshimchaKalitlar.clear();

      for (final item in javob) {
        final kalit = item['kalit'] as String;
        if (_yashiriladiganKalitlar.contains(kalit)) continue;

        _kontrollerlar.putIfAbsent(kalit, () {
          if (!malumKalitlar.contains(kalit)) _qoshimchaKalitlar.add(kalit);
          _matnKorinadi[kalit] = false;
          return TextEditingController();
        });
        _kontrollerlar[kalit]!.text = (item['qiymat'] as String?) ?? '';
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _saqlash(String kalit) async {
    final holat = context.read<AppState>();
    setState(() => _saqlanmoqda[kalit] = true);
    try {
      await holat.api.put('/sozlamalar/$kalit', tana: {'qiymat': _kontrollerlar[kalit]!.text});
      if (mounted) _xabarKorsat(holat.lok.t('sozlama_saqlandi'), xato: false);
    } catch (e) {
      if (mounted) _xabarKorsat(e.toString(), xato: true);
    } finally {
      if (mounted) setState(() => _saqlanmoqda[kalit] = false);
    }
  }

  void _xabarKorsat(String matn, {required bool xato}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(matn), backgroundColor: xato ? Colors.red.shade700 : Colors.green.shade700));
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lok.t('sozlamalar'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (_yuklanmoqda) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (_xato != null) Expanded(child: Center(child: Text(_xato!))),
          if (!_yuklanmoqda && _xato == null) Expanded(child: _tarkib(lok)),
        ],
      ),
    );
  }

  Widget _tarkib(dynamic lok) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bolim in _bolimlar) _bolimKartasi(lok.t(bolim.sarlavhaKaliti), bolim.maydonlar, lok),
          if (_qoshimchaKalitlar.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(lok.t('boshqa_sozlamalar'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final kalit in _qoshimchaKalitlar) ...[
                      _maydonQatori(_SozlamaMaydoni(kalit: kalit, labelKaliti: kalit), lok, xomLabel: true),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bolimKartasi(String sarlavha, List<_SozlamaMaydoni> maydonlar, dynamic lok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sarlavha, style: Theme.of(context).textTheme.titleMedium),
              for (final maydon in maydonlar) ...[
                const SizedBox(height: 12),
                _maydonQatori(maydon, lok),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _maydonQatori(_SozlamaMaydoni maydon, dynamic lok, {bool xomLabel = false}) {
    final kontroller = _kontrollerlar[maydon.kalit]!;
    final korinadi = _matnKorinadi[maydon.kalit] ?? false;
    final saqlanmoqda = _saqlanmoqda[maydon.kalit] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (maydon.tavsifKaliti != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(lok.t(maydon.tavsifKaliti), style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: kontroller,
                obscureText: maydon.maxfiy && !korinadi,
                decoration: InputDecoration(
                  labelText: xomLabel ? maydon.labelKaliti : lok.t(maydon.labelKaliti),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: maydon.maxfiy
                      ? IconButton(
                          icon: Icon(korinadi ? Icons.visibility_off : Icons.visibility),
                          tooltip: korinadi ? lok.t('parolni_yashirish') : lok.t('parolni_korsatish'),
                          onPressed: () => setState(() => _matnKorinadi[maydon.kalit] = !korinadi),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: saqlanmoqda ? null : () => _saqlash(maydon.kalit),
              child: saqlanmoqda
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(lok.t('saqlash')),
            ),
          ],
        ),
      ],
    );
  }
}
