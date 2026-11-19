import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/member_level_guide.dart';

void main() {
  testWidgets('the profile guide scrolls and closes on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(340, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MemberLevelGuideButton(profileLevel: 1)),
      ),
    );

    await tester.tap(find.text('Level guide'));
    await tester.pumpAndSettle();
    expect(find.text('Level 1 · Newcomer'), findsOneWidget);
    expect(find.text('Profile level'), findsOneWidget);
    expect(
      find.textContaining(
        'Up to 2 open at once · Up to 4 published in any 30 days',
      ),
      findsOneWidget,
    );

    final verification = find.textContaining(
      'identity verification is currently unavailable',
    );
    await tester.scrollUntilVisible(verification, 180);
    expect(verification, findsOneWidget);
    expect(find.textContaining('at least 51 likes'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Level guide'), findsOneWidget);
    expect(find.text('Profile level'), findsNothing);
  });
}
