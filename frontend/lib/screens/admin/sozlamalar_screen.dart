import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../models/foydalanuvchi.dart';
import '../../state/app_state.dart';
import '../../theme.dart';

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
  (
    sarlavhaKaliti: 'telegram_surat_bolimi',
    maydonlar: [
      _SozlamaMaydoni(
        kalit: 'telegram_surat_bot_token',
        labelKaliti: 'telegram_surat_bot_token',
        tavsifKaliti: 'telegram_surat_tavsif',
        maxfiy: true,
      ),
      _SozlamaMaydoni(kalit: 'telegram_surat_chat_id', labelKaliti: 'telegram_surat_chat_id'),
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

  List<Foydalanuvchi> _foydalanuvchilar = [];

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
      final api = context.read<AppState>().api;
      final javob = await api.get('/sozlamalar') as List;
      // Javob kelguncha ekran dispose bo'lgan bo'lishi mumkin — bunday holda
      // pastdagi tsikl allaqachon dispose qilingan TextEditingController'larga
      // yozishga urinib qolmasligi uchun darhol to'xtaymiz.
      if (!mounted) return;

      // Foydalanuvchilar ro'yxati — alohida, "yumshoq" so'rov: uni olib
      // bo'lmasa ham asosiy sozlamalar ekrani ishlashda davom etadi.
      try {
        final fRoyxat = await api.get('/foydalanuvchilar') as List;
        if (!mounted) return;
        _foydalanuvchilar =
            fRoyxat.map((e) => Foydalanuvchi.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _foydalanuvchilar = [];
      }

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
          _foydalanuvchilarKartasi(lok),
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

  // --- Foydalanuvchilar bo'limi ---

  static const _rolRanglari = {
    'admin': kipTaroziYashil,
    'operator': Color(0xFF3B82C4),
    'tayyor_mahsulotlar': Color(0xFFD98B2B),
  };

  Color _rolRangi(String rol) => _rolRanglari[rol] ?? Colors.grey;

  IconData _rolIkonkasi(String rol) {
    switch (rol) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'operator':
        return Icons.engineering;
      default:
        return Icons.inventory_2;
    }
  }

  String _rolNomi(String rol, dynamic lok) {
    switch (rol) {
      case 'admin':
        return lok.t('admin_rol');
      case 'operator':
        return lok.t('operator');
      default:
        return lok.t('tayyor_mahsulotlar_rol');
    }
  }

  Widget _foydalanuvchilarKartasi(dynamic lok) {
    if (_foydalanuvchilar.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lok.t('foydalanuvchilar'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                lok.t('foydalanuvchilar_tavsif'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final f in _foydalanuvchilar) _foydalanuvchiQatori(f, lok),
            ],
          ),
        ),
      ),
    );
  }

  Widget _foydalanuvchiQatori(Foydalanuvchi f, dynamic lok) {
    final rang = _rolRangi(f.rol);
    final ozimi = context.read<AppState>().foydalanuvchi?.id == f.id;
    final tafsilot = f.rol == 'operator' && f.smena != null
        ? '${_rolNomi(f.rol, lok)} · ${lok.t('smena')} ${f.smena}'
        : _rolNomi(f.rol, lok);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: rang.withValues(alpha: 0.15),
            child: Icon(_rolIkonkasi(f.rol), color: rang, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('@${f.login}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    if (ozimi) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.person, size: 14, color: Colors.grey.shade500),
                    ],
                  ],
                ),
                Text(tafsilot, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: Text(lok.t('tahrirlash')),
            onPressed: () => _hisobniTahrirlash(f),
          ),
        ],
      ),
    );
  }

  Future<void> _hisobniTahrirlash(Foydalanuvchi f) async {
    final holat = context.read<AppState>();
    final lok = holat.lok;
    final ozimi = holat.foydalanuvchi?.id == f.id;

    final loginKontroller = TextEditingController();
    final parolKontroller = TextEditingController();
    var parolKorinadi = false;
    var saqlanmoqda = false;
    String? xato;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> saqla() async {
            final yangiLogin = loginKontroller.text.trim();
            final yangiParol = parolKontroller.text;
            if (yangiLogin.isEmpty && yangiParol.isEmpty) {
              setDialogState(() => xato = lok.t('kamida_bitta_maydon'));
              return;
            }

            if (ozimi) {
              final davom = await showDialog<bool>(
                context: dialogContext,
                builder: (c) => AlertDialog(
                  title: Text(lok.t('hisobni_tahrirlash')),
                  content: Text(lok.t('oz_hisob_ogohlantirish')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(lok.t('bekor'))),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(lok.t('davom_etish'))),
                  ],
                ),
              );
              if (davom != true) return;
            }

            setDialogState(() {
              saqlanmoqda = true;
              xato = null;
            });
            try {
              final tana = <String, dynamic>{};
              if (yangiLogin.isNotEmpty) tana['login'] = yangiLogin;
              if (yangiParol.isNotEmpty) tana['parol'] = yangiParol;
              await holat.api.patch('/foydalanuvchilar/${f.id}', tana: tana);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) {
                _xabarKorsat(lok.t('foydalanuvchi_yangilandi'), xato: false);
                _yuklash();
              }
            } on ApiException catch (e) {
              setDialogState(() => xato = e.xabar);
            } catch (e) {
              setDialogState(() => xato = e.toString());
            } finally {
              setDialogState(() => saqlanmoqda = false);
            }
          }

          return AlertDialog(
            title: Text('${lok.t('hisobni_tahrirlash')} — @${f.login}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lok.t('bosh_qoldirilsa_ozgarmaydi'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loginKontroller,
                  decoration: InputDecoration(
                    labelText: lok.t('yangi_login'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parolKontroller,
                  obscureText: !parolKorinadi,
                  decoration: InputDecoration(
                    labelText: lok.t('yangi_parol'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(parolKorinadi ? Icons.visibility_off : Icons.visibility),
                      tooltip: parolKorinadi ? lok.t('parolni_yashirish') : lok.t('parolni_korsatish'),
                      onPressed: () => setDialogState(() => parolKorinadi = !parolKorinadi),
                    ),
                  ),
                ),
                if (xato != null) ...[
                  const SizedBox(height: 12),
                  Text(xato!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saqlanmoqda ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(lok.t('bekor_qilish')),
              ),
              FilledButton(
                onPressed: saqlanmoqda ? null : saqla,
                child: saqlanmoqda
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(lok.t('saqlash')),
              ),
            ],
          );
        },
      ),
    );

    loginKontroller.dispose();
    parolKontroller.dispose();
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
