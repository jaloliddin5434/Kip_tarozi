import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Login ekranining gradient foni — 135° (yuqori chapdan pastki o'ngga),
/// to'q yashildan ochroq yashilgacha.
const _fonGradienti = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0A4F3D), Color(0xFF0F6E56), Color(0xFF1D9E75)],
);

/// Kartochka QAT'IY maksimal kenglikda — "iloji boricha katta" emas.
const _kartochkaKengligi = 440.0;

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
  // Faqat rol == 'operator' bo'lganda ishlatiladi: 'A' | 'B' | 'C' | 'D' | null
  String? _tanlanganSmena;

  Future<void> _kirish() async {
    final holat = context.read<AppState>();
    final login = _tanlanganRol == 'operator'
        ? 'operator_${_tanlanganSmena!.toLowerCase()}'
        : _loginKontrolleri.text.trim();

    setState(() {
      _yuklanmoqda = true;
      _xato = null;
    });
    try {
      await holat.kirish(login, _parolKontrolleri.text);
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

  void _smenaniTanlash(String smena) {
    setState(() {
      _tanlanganSmena = smena;
      _xato = null;
    });
  }

  void _rolTanlashgaQaytish() {
    setState(() {
      _tanlanganRol = null;
      _tanlanganSmena = null;
      _xato = null;
      _loginKontrolleri.clear();
      _parolKontrolleri.clear();
    });
  }

  void _smenaTanlashgaQaytish() {
    setState(() {
      _tanlanganSmena = null;
      _xato = null;
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

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;
    final smenaTanlashQadami = _tanlanganRol == 'operator' && _tanlanganSmena == null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: _fonGradienti),
        child: Stack(
          children: [
            // Faqat bezak uchun — funksional emas.
            const Positioned(top: -70, left: -50, child: _DekorativDoira(olcham: 200, shaffoflik: 0.07)),
            const Positioned(bottom: -90, right: -60, child: _DekorativDoira(olcham: 260, shaffoflik: 0.06)),
            const Positioned(top: 140, right: -20, child: _DekorativDoira(olcham: 90, shaffoflik: 0.09)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _kartochkaKengligi),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 44, offset: const Offset(0, 22)),
                              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _logotip(lok),
                              const SizedBox(height: 22),
                              if (_tanlanganRol == null)
                                _SalomlashuvQutisi(lok: lok)
                              else
                                ..._sarlavhaOstQismi(lok, smenaTanlashQadami),
                              const SizedBox(height: 26),
                              if (_tanlanganRol == null) ...[
                                _kichikYorliq(lok.t('rolni_tanlang')),
                                const SizedBox(height: 12),
                              ],
                              if (_tanlanganRol == null)
                                ..._rolTanlashQadami(lok)
                              else if (smenaTanlashQadami)
                                ..._smenaTanlashQadami(lok)
                              else
                                ..._kirishQadami(lok),
                              const SizedBox(height: 22),
                              _tilTanlashQatori(holat),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      _shior(lok),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logotip(dynamic lok) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F6E56), Color(0xFF1D9E75)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: kipTaroziYashil.withValues(alpha: 0.38), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: const Icon(Icons.scale, color: Colors.white, size: 44),
        ),
        const SizedBox(height: 16),
        Text(
          lok.t('login_sarlavha'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF16281F)),
        ),
        const SizedBox(height: 4),
        Text(
          lok.t('xazorasp_textil'),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.4, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _kichikYorliq(String matn) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        matn.toUpperCase(),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, letterSpacing: 1.3, color: Colors.grey.shade500),
      ),
    );
  }

  Widget _tilTanlashQatori(AppState holat) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TilPilli(matn: 'UZ', tanlanganmi: holat.til == Til.uz, onTap: () {
          if (holat.til != Til.uz) holat.tilniAlmashtirish();
        }),
        const SizedBox(width: 10),
        _TilPilli(matn: 'RU', tanlanganmi: holat.til == Til.ru, onTap: () {
          if (holat.til != Til.ru) holat.tilniAlmashtirish();
        }),
      ],
    );
  }

  Widget _shior(dynamic lok) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.balance, size: 16, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            lok.t('login_shior'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Rol/smena allaqachon tanlangan bosqichlarda ko'rsatiladigan holat
  /// qatori — funksionalligi o'zgarmagan, faqat yangi kartochka ichiga
  /// ko'chirilgan.
  List<Widget> _sarlavhaOstQismi(dynamic lok, bool smenaTanlashQadami) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_rolIkonkasi(_tanlanganRol!), size: 18, color: kipTaroziYashil),
          const SizedBox(width: 6),
          Text(
            _rolNomi(_tanlanganRol!, lok),
            style: const TextStyle(color: kipTaroziYashil, fontWeight: FontWeight.bold),
          ),
          if (_tanlanganSmena != null) ...[
            const Text(' — ', style: TextStyle(color: kipTaroziYashil)),
            Text(
              '${lok.t("smena")} $_tanlanganSmena',
              style: const TextStyle(color: kipTaroziYashil, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
      if (smenaTanlashQadami) ...[
        const SizedBox(height: 6),
        Text(lok.t('smenani_tanlang'), style: const TextStyle(color: Colors.grey)),
      ],
    ];
  }

  List<Widget> _rolTanlashQadami(dynamic lok) {
    return [
      _RolTugmasi(
        ikonka: Icons.admin_panel_settings,
        matn: lok.t('admin_rol'),
        rang: kipTaroziYashil,
        onTap: () => _rolniTanlash('admin'),
      ),
      const SizedBox(height: 12),
      _RolTugmasi(
        ikonka: Icons.engineering,
        matn: lok.t('operator'),
        rang: mahsulotRangi('lint'),
        onTap: () => _rolniTanlash('operator'),
      ),
      const SizedBox(height: 12),
      _RolTugmasi(
        ikonka: Icons.inventory_2,
        matn: lok.t('tayyor_mahsulotlar_rol'),
        rang: mahsulotRangi('pux'),
        onTap: () => _rolniTanlash('tayyor_mahsulotlar'),
      ),
    ];
  }

  List<Widget> _smenaTanlashQadami(dynamic lok) {
    return [
      Row(
        children: [
          Expanded(child: _smenaTugmasi('A')),
          const SizedBox(width: 12),
          Expanded(child: _smenaTugmasi('B')),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _smenaTugmasi('C')),
          const SizedBox(width: 12),
          Expanded(child: _smenaTugmasi('D')),
        ],
      ),
      const SizedBox(height: 20),
      _orqagaTugmasi(lok, onPressed: _rolTanlashgaQaytish),
    ];
  }

  Widget _smenaTugmasi(String smena) {
    return SizedBox(
      height: 80,
      child: OutlinedButton(
        onPressed: () => _smenaniTanlash(smena),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: kipTaroziYashil),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          smena,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: kipTaroziYashil),
        ),
      ),
    );
  }

  Widget _orqagaTugmasi(dynamic lok, {required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _yuklanmoqda ? null : onPressed,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [const Icon(Icons.arrow_back, size: 18), const SizedBox(width: 4), Text(lok.t('orqaga'))],
        ),
      ),
    );
  }

  List<Widget> _kirishQadami(dynamic lok) {
    final operatorMi = _tanlanganRol == 'operator';
    return [
      if (!operatorMi) ...[
        TextField(
          controller: _loginKontrolleri,
          decoration: InputDecoration(labelText: lok.t('login_belgi'), border: const OutlineInputBorder()),
          onSubmitted: (_) => _kirish(),
          autofocus: true,
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _parolKontrolleri,
        decoration: InputDecoration(labelText: lok.t('parol_belgi'), border: const OutlineInputBorder()),
        obscureText: true,
        autofocus: operatorMi,
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
            onPressed: _yuklanmoqda ? null : (operatorMi ? _smenaTanlashgaQaytish : _rolTanlashgaQaytish),
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

/// Faqat bezak uchun ishlatiladigan shaffof doira — funksional emas.
class _DekorativDoira extends StatelessWidget {
  final double olcham;
  final double shaffoflik;
  const _DekorativDoira({required this.olcham, required this.shaffoflik});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: olcham,
      height: olcham,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: shaffoflik)),
    );
  }
}

/// Rol tanlanmagan bosqichda logotip ostida ko'rsatiladigan salomlashuv
/// qutisi — yengil yashil fon-tint bilan.
class _SalomlashuvQutisi extends StatelessWidget {
  final dynamic lok;
  const _SalomlashuvQutisi({required this.lok});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: kipTaroziYashil.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            lok.t('login_salomlashuv_sarlavha'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0A4F3D)),
          ),
          const SizedBox(height: 2),
          Text(
            lok.t('login_salomlashuv_matn'),
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

/// Rol tanlash tugmasi — rangli ikonka-kvadrat, nom va rangli strelka bilan.
/// Sichqoncha kelganda (faqat web/desktop, touch'da ta'sir qilmaydi) biroz
/// kattalashadi va soyasi kuchayadi.
class _RolTugmasi extends StatefulWidget {
  final IconData ikonka;
  final String matn;
  final Color rang;
  final VoidCallback onTap;

  const _RolTugmasi({required this.ikonka, required this.matn, required this.rang, required this.onTap});

  @override
  State<_RolTugmasi> createState() => _RolTugmasiState();
}

class _RolTugmasiState extends State<_RolTugmasi> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: widget.rang.withValues(alpha: _hover ? 0.28 : 0.10),
                    blurRadius: _hover ? 22 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.rang.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.ikonka, color: widget.rang, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.matn,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: widget.rang),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Til tanlash "pill" tugmasi — tanlangani yashil fon bilan to'ldirilgan.
class _TilPilli extends StatelessWidget {
  final String matn;
  final bool tanlanganmi;
  final VoidCallback onTap;

  const _TilPilli({required this.matn, required this.tanlanganmi, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tanlanganmi ? kipTaroziYashil : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            matn,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              color: tanlanganmi ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}
