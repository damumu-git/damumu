import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/member_level_guide.dart';

void main() {
  testWidgets(
    'the guide opens at the profile level and shows each medal and quota',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(340, 590));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MemberLevelGuideButton(profileLevel: 2)),
        ),
      );

      await tester.tap(find.text('Level guide'));
      await tester.pumpAndSettle();
      expect(find.byType(MemberMedal), findsNWidgets(4));
      expect(find.text('Junior host'), findsOneWidget);
      expect(find.text('Profile level'), findsOneWidget);
      expect(find.text('Successfully host 3+ activities'), findsOneWidget);

      await tester.tap(find.text('Lv3'));
      await tester.pumpAndSettle();
      expect(find.text('Standout host'), findsOneWidget);
      expect(find.text('Profile level'), findsNothing);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      await tester.tap(find.text('Lv4'));
      await tester.pumpAndSettle();
      expect(find.text('Gold host'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.textContaining('Up to 12 per plan'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Level guide'), findsOneWidget);
      expect(find.byType(MemberMedal), findsNothing);
    },
  );
}
