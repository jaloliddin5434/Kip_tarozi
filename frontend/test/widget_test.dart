import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kip_tarozi/main.dart';

void main() {
  testWidgets('Kirilmagan holatda login ekrani ko\'rinadi', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const KipTaroziApp());
    await tester.pumpAndSettle();

    // Login ekrani endi avval ROL tanlashni talab qiladi (Admin/Operator/
    // Tayyor mahsulotlar) — Login/Parol maydonlari faqat rol tanlangandan
    // keyin ko'rinadi. Shuning uchun "Admin" rolini tanlaymiz (u to'g'ridan
    // to'g'ri Login/Parol qadamiga o'tadi — operatordan farqli, smena
    // tanlash bosqichisiz).
    expect(find.text('Admin'), findsOneWidget, reason: 'Rol tanlash qadami ko\'rinishi kerak');
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Parol'), findsOneWidget);
  });
}
