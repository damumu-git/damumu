import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/event_service.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets('publisher can explicitly choose whether approval is required', (
    tester,
  ) async {
    var approvalRequired = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ApprovalModeSelector(
              value: approvalRequired,
              onChanged: (value) => setState(() => approvalRequired = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('是否需要审核'), findsOneWidget);
    expect(find.text('申请者需经你确认后才能加入活动'), findsOneWidget);
    await tester.tap(find.text('无需审核'));
    await tester.pumpAndSettle();
    expect(approvalRequired, isFalse);
    expect(find.text('申请后立即加入活动，无需组织者确认'), findsOneWidget);
  });

  test('approval choice is sent as the matching API mode', () async {
    final receivedModes = <String>[];
    final client = MockClient((request) async {
      receivedModes.add(
        (jsonDecode(request.body) as Map<String, dynamic>)['approvalMode']
            as String,
      );
      return http.Response(
        jsonEncode({
          'data': {'id': 'event-id'},
        }),
        200,
      );
    });

    await http.runWithClient(() async {
      for (final required in [true, false]) {
        await EventService.create(
          token: 'token',
          categoryId: 'category-id',
          title: '测试活动',
          description: '活动说明',
          cityCode: 'city',
          districtCode: 'district',
          startsAt: DateTime.utc(2026, 10, 1, 10),
          endsAt: DateTime.utc(2026, 10, 1, 12),
          capacity: 8,
          priceAmount: 0,
          approvalRequired: required,
        );
      }
    }, () => client);

    expect(receivedModes, ['manual', 'automatic']);
  });
}
