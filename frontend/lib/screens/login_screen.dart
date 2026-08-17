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

  // 'admin' | 'operator' | 'tayyor_mahsulotlar' | null (hali tanlanmagan)
  String? _tanlanganRol;

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

  void _rolniTanlash(String rol) {
    setState(() {
      _tanlanganRol = rol;
      _xato = null;
    });
  }

  void _rolTanlashgaQaytish() {
    setState(() {
      _tanlanganRol = null;
      _xato = null;
      _loginKontrolleri.clear();
      _parolKontrolleri.clear();
    });
  }

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

  String _loginYorlagi(String rol, dynamic lok) {
    return rol == 'operator' ? lok.t('smena_login_belgi') : lok.t('login_belgi');
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
                const SizedBox(height: 8),
                if (_tanlanganRol == null)
                  Text(lok.t('rolni_tanlang'), style: const TextStyle(color: Colors.grey))
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_rolIkonkasi(_tanlanganRol!), size: 18, color: kipTaroziYashil),
                      const SizedBox(width: 6),
                      Text(
                        _rolNomi(_tanlanganRol!, lok),
                        style: const TextStyle(color: kipTaroziYashil, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                const SizedBox(height: 28),
                if (_tanlanganRol == null) ..._rolTanlashQadami(lok) else ..._kirishQadami(lok),
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

  List<Widget> _rolTanlashQadami(dynamic lok) {
    return [
      _rolTugmasi(ikonka: Icons.admin_panel_settings, matn: lok.t('admin_rol'), rol: 'admin'),
      const SizedBox(height: 12),
      _rolTugmasi(ikonka: Icons.engineering, matn: lok.t('operator'), rol: 'operator'),
      const SizedBox(height: 12),
      _rolTugmasi(ikonka: Icons.inventory_2, matn: lok.t('tayyor_mahsulotlar_rol'), rol: 'tayyor_mahsulotlar'),
    ];
  }

  Widget _rolTugmasi({required IconData ikonka, required String matn, required String rol}) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: OutlinedButton(
        onPressed: () => _rolniTanlash(rol),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kipTaroziYashil),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Icon(ikonka, size: 28, color: kipTaroziYashil),
            const SizedBox(width: 16),
            Expanded(
              child: Text(matn, style: const TextStyle(fontSize: 16), textAlign: TextAlign.left),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  List<Widget> _kirishQadami(dynamic lok) {
    return [
      TextField(
        controller: _loginKontrolleri,
        decoration: InputDecoration(labelText: _loginYorlagi(_tanlanganRol!, lok), border: const OutlineInputBorder()),
        onSubmitted: (_) => _kirish(),
        autofocus: true,
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
      Row(
        children: [
          OutlinedButton(
            onPressed: _yuklanmoqda ? null : _rolTanlashgaQaytish,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Row(
              children: [const Icon(Icons.arrow_back, size: 18), const SizedBox(width: 4), Text(lok.t('orqaga'))],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _yuklanmoqda ? null : _kirish,
              child: _yuklanmoqda
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(lok.t('kirish')),
            ),
          ),
        ],
      ),
    ];
  }
}
