import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../state/app_state.dart';

class MoliyaviyKirishEkrani extends StatefulWidget {
  const MoliyaviyKirishEkrani({super.key});

  @override
  State<MoliyaviyKirishEkrani> createState() => _MoliyaviyKirishEkraniState();
}

class _MoliyaviyKirishEkraniState extends State<MoliyaviyKirishEkrani> {
  final _parolKontrolleri = TextEditingController();
  final _tasdiqParolKontrolleri = TextEditingController();
  bool _ornatishRejimi = false;
  bool _yuklanmoqda = false;
  String? _xato;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sessiyaniTekshirish());
  }

  void _sessiyaniTekshirish() {
    final holat = context.read<AppState>();
    if (holat.moliyaviySessiyaAmalda) {
      _hisobotSahifasigaOtish();
    } else if (holat.moliyaviyToken != null) {
      holat.moliyaviyChiqish();
      setState(() => _xato = holat.lok.t('moliyaviy_sessiya_tugadi'));
    }
  }

  Future<void> _kirish() async {
    final holat = context.read<AppState>();
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      await holat.moliyaviyKirish(_parolKontrolleri.text);
      if (mounted) _hisobotSahifasigaOtish();
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        setState(() => _ornatishRejimi = true);
      } else if (e.statusCode == 401) {
        setState(() => _xato = holat.lok.t('moliyaviy_parol_notogri'));
      } else {
        setState(() => _xato = e.xabar);
      }
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  Future<void> _parolniOrnatish() async {
    final holat = context.read<AppState>();
    if (_parolKontrolleri.text != _tasdiqParolKontrolleri.text) {
      setState(() => _xato = holat.lok.t('parollar_mos_emas'));
      return;
    }
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      await holat.moliyaviyParolOrnatish(_parolKontrolleri.text);
      await holat.moliyaviyKirish(_parolKontrolleri.text);
      if (mounted) _hisobotSahifasigaOtish();
    } on ApiException catch (e) {
      setState(() => _xato = e.xabar);
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  void _hisobotSahifasigaOtish() {
    final lok = context.read<AppState>().lok;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(lok.t('moliyaviy'))),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(lok.t('tez_orada'), style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lok = context.watch<AppState>().lok;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.lock, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                Text(lok.t('moliyaviy'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (_ornatishRejimi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      lok.t('moliyaviy_birinchi_marta_matni'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _parolKontrolleri,
                  decoration: InputDecoration(labelText: lok.t('moliyaviy_parol'), border: const OutlineInputBorder()),
                  obscureText: true,
                  onSubmitted: (_) => _ornatishRejimi ? _parolniOrnatish() : _kirish(),
                ),
                if (_ornatishRejimi) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tasdiqParolKontrolleri,
                    decoration: InputDecoration(
                      labelText: lok.t('moliyaviy_parol_tasdiqlash'),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    onSubmitted: (_) => _parolniOrnatish(),
                  ),
                ],
                if (_xato != null) ...[
                  const SizedBox(height: 12),
                  Text(_xato!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _yuklanmoqda ? null : (_ornatishRejimi ? _parolniOrnatish : _kirish),
                    child: _yuklanmoqda
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_ornatishRejimi ? lok.t('moliyaviy_parol_ornatish') : lok.t('kirish')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
