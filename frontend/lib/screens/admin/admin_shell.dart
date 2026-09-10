import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../widgets/clock_widget.dart';
import 'dashboard_screen.dart';
import 'hujjatlar_screen.dart';
import 'kamera_tasdiqlari_screen.dart';
import 'kip_togrilash_screen.dart';
import 'moliyaviy_kirish_screen.dart';
import 'partiyalar_screen.dart';
import 'shubhali_holatlar_screen.dart';
import 'sozlamalar_screen.dart';
import 'statistika_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tanlanganIndeks = 0;

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();
    final lok = holat.lok;
    final tayyorMahsulotRoli = holat.foydalanuvchi?.rol == 'tayyor_mahsulotlar';
    final adminRoli = holat.foydalanuvchi?.rol == 'admin';

    final sahifalar = [
      if (!tayyorMahsulotRoli) const DashboardEkrani(),
      const HujjatlarEkrani(),
      if (!tayyorMahsulotRoli) const StatistikaEkrani(),
      const PartiyalarEkrani(),
      if (!tayyorMahsulotRoli) const ShubhaliHolatlarEkrani(),
      if (adminRoli) const KameraTasdiqlariEkrani(),
      if (adminRoli) const KipTogrilashEkrani(),
      if (adminRoli) const MoliyaviyKirishEkrani(),
      if (adminRoli) const SozlamalarEkrani(),
    ];
    final yorliqlar = [
      if (!tayyorMahsulotRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.dashboard),
          label: Text(lok.t('dashboard')),
        ),
      NavigationRailDestination(
        icon: const Icon(Icons.description),
        label: Text(lok.t('hujjatlar')),
      ),
      if (!tayyorMahsulotRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.bar_chart),
          label: Text(lok.t('statistika')),
        ),
      NavigationRailDestination(
        icon: const Icon(Icons.folder),
        label: Text(lok.t('partiyalar')),
      ),
      if (!tayyorMahsulotRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.warning_amber_rounded),
          label: Text(lok.t('shubhali_holatlar_royxati')),
        ),
      if (adminRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(lok.t('kamera_tasdiqlari')),
        ),
      if (adminRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.edit_note),
          label: Text(lok.t('kip_togrilash_sorovlari')),
        ),
      if (adminRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.lock),
          label: Text(lok.t('moliyaviy')),
        ),
      if (adminRoli)
        NavigationRailDestination(
          icon: const Icon(Icons.settings),
          label: Text(lok.t('sozlamalar')),
        ),
    ];

    // Rol o'zgarishi (masalan qayta login) sahifalar sonini qisqartirishi mumkin —
    // _tanlanganIndeks'ni build() ichida to'g'ridan-to'g'ri o'zgartirish o'rniga,
    // faqat shu render uchun mahalliy tuzatilgan qiymatdan foydalanamiz.
    final effektivIndeks = _tanlanganIndeks >= sahifalar.length ? 0 : _tanlanganIndeks;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Kip Tarozi — Admin (${holat.foydalanuvchi?.ism ?? ""})',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: SoatWidget()),
          ),
          IconButton(
            icon: Icon(
              holat.temaRejimi == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () => holat.temaniAlmashtirish(),
          ),
          TextButton(
            onPressed: () => holat.tilniAlmashtirish(),
            child: Text(
              holat.til.name.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => holat.chiqish(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: effektivIndeks,
            onDestinationSelected: (i) => setState(() => _tanlanganIndeks = i),
            labelType: NavigationRailLabelType.all,
            destinations: yorliqlar,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(index: effektivIndeks, children: sahifalar),
          ),
        ],
      ),
    );
  }
}
