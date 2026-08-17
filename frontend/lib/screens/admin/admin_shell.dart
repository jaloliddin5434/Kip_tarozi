import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../widgets/clock_widget.dart';
import 'dashboard_screen.dart';
import 'hujjatlar_screen.dart';
import 'moliyaviy_kirish_screen.dart';
import 'partiyalar_screen.dart';
import 'shubhali_holatlar_screen.dart';
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
      if (!tayyorMahsulotRoli) const PartiyalarEkrani(),
      if (!tayyorMahsulotRoli) const ShubhaliHolatlarEkrani(),
      if (adminRoli) const MoliyaviyKirishEkrani(),
    ];
    final yorliqlar = [
      if (!tayyorMahsulotRoli) NavigationRailDestination(icon: const Icon(Icons.dashboard), label: Text(lok.t('dashboard'))),
      NavigationRailDestination(icon: const Icon(Icons.description), label: Text(lok.t('hujjatlar'))),
      if (!tayyorMahsulotRoli) NavigationRailDestination(icon: const Icon(Icons.bar_chart), label: Text(lok.t('statistika'))),
      if (!tayyorMahsulotRoli) NavigationRailDestination(icon: const Icon(Icons.folder), label: Text(lok.t('partiyalar'))),
      if (!tayyorMahsulotRoli)
        NavigationRailDestination(icon: const Icon(Icons.warning_amber_rounded), label: Text(lok.t('shubhali_holatlar_royxati'))),
      if (adminRoli) NavigationRailDestination(icon: const Icon(Icons.lock), label: Text(lok.t('moliyaviy'))),
    ];

    if (_tanlanganIndeks >= sahifalar.length) _tanlanganIndeks = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Kip Tarozi — Admin (${holat.foydalanuvchi?.ism ?? ""})', overflow: TextOverflow.ellipsis),
        actions: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Center(child: SoatWidget())),
          IconButton(
            icon: Icon(holat.temaRejimi == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => holat.temaniAlmashtirish(),
          ),
          TextButton(
            onPressed: () => holat.tilniAlmashtirish(),
            child: Text(holat.til.name.toUpperCase(), style: const TextStyle(color: Colors.white)),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => holat.chiqish()),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tanlanganIndeks,
            onDestinationSelected: (i) => setState(() => _tanlanganIndeks = i),
            labelType: NavigationRailLabelType.all,
            destinations: yorliqlar,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: sahifalar[_tanlanganIndeks]),
        ],
      ),
    );
  }
}
