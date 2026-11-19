import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/main.dart';
import 'package:zaihandazi/recurring_activities.dart';

void main() {
  testWidgets('recurring plan publishes only the selected occurrence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final published = <String>[];
    String? opened;
    final client = MockClient((request) async {
      Object data;
      if (request.method == 'POST') {
        published.add(request.url.path);
        data = {'id': 'created-event'};
      } else {
        data = [
          {
            'id': 'plan',
            'title': 'Weekly plan',
            'frequency': 'weekly',
            'paused': false,
            'occurrences': [
              {
                'index': 1,
                'startsAt': '2099-01-01T10:00:00Z',
                'endsAt': '2099-01-01T12:00:00Z',
                'canPublish': true,
              },
            ],
          },
        ];
      }
      return http.Response(jsonEncode({'data': data}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          home: RecurringPlansPage(
            token: 'fixture',
            openEvent: (_, id) async {
              opened = id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(published, isEmpty);
      await tester.tap(find.text('Weekly plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(published, ['/api/v1/recurring-events/plan/occurrences/1']);
      expect(opened, 'created-event');
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
