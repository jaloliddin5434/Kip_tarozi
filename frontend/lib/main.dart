import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/login_screen.dart';
import 'screens/operator/operator_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  runApp(const KipTaroziApp());
}

class KipTaroziApp extends StatelessWidget {
  const KipTaroziApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..tiklash(),
      child: Consumer<AppState>(
        builder: (context, holat, _) {
          return MaterialApp(
            title: 'Kip Tarozi',
            debugShowCheckedModeBanner: false,
            theme: yorugRejim(),
            darkTheme: qorongiRejim(),
            themeMode: holat.temaRejimi,
            home: const _AsosiyYonaltiruvchi(),
          );
        },
      ),
    );
  }
}

class _AsosiyYonaltiruvchi extends StatelessWidget {
  const _AsosiyYonaltiruvchi();

  @override
  Widget build(BuildContext context) {
    final holat = context.watch<AppState>();

    if (!holat.kirilgan) return const LoginEkrani();

    if (holat.foydalanuvchi!.rol == 'operator') return const OperatorEkrani();
    return const AdminShell();
  }
}
