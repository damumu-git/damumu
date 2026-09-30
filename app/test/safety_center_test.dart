import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets('emergency actions do not offer 112 or 119 dialing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const DaziApp(home: SafetyCenterPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('需要紧急帮助'));
    await tester.tap(find.text('需要紧急帮助'));
    await tester.pumpAndSettle();

    expect(find.textContaining('拨打 112'), findsNothing);
    expect(find.textContaining('拨打 119'), findsNothing);
    expect(find.text('通知紧急联系人并分享位置'), findsOneWidget);
  });
}
