import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme.dart';

class LoginEkrani extends StatefulWidget {
  const LoginEkrani({super.key});

  @override
  State<LoginEkrani> createState() => _LoginEkraniState();
}

class _LoginEkraniState extends State<LoginEkrani> {
  final _loginKontrolleri = TextEditingController();
  final _parolKontrolleri = TextEditingController();
  bool _yuklanmoqda = false;
  String? _xato;

  Future<void> _kirish() async {
    final holat = context.read<AppState>();
    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      await holat.kirish(_loginKontrolleri.text.trim(), _parolKontrolleri.text);
    } catch (e) {
      setState(() => _xato = e.toString());
    } finally {
      if (mounted) setState(() => _yuklanmoqda = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;

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
                  decoration: BoxDecoration(color: kipTaroziYashil, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.scale, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 16),
                Text(lok.t('login_sarlavha'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 32),
                TextField(
                  controller: _loginKontrolleri,
                  decoration: InputDecoration(labelText: lok.t('login_belgi'), border: const OutlineInputBorder()),
                  onSubmitted: (_) => _kirish(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _parolKontrolleri,
                  decoration: InputDecoration(labelText: lok.t('parol_belgi'), border: const OutlineInputBorder()),
                  obscureText: true,
                  onSubmitted: (_) => _kirish(),
                ),
                if (_xato != null) ...[
                  const SizedBox(height: 12),
                  Text(_xato!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _yuklanmoqda ? null : _kirish,
                    child: _yuklanmoqda
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(lok.t('kirish')),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => holat.tilniAlmashtirish(),
                  child: Text(holat.til.name.toUpperCase()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
