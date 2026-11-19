import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets('my activities loads another page and searches on the server', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      expect(request.url.path, '/api/v1/me/activities');
      expect(request.url.queryParameters['limit'], '20');
      final searching = request.url.queryParameters['q'] == 'needle';
      final next = request.url.queryParameters['cursor'] != null;
      final count = searching
          ? 0
          : next
          ? 1
          : 20;
      final data = {
        'items': [
          for (var index = 0; index < count; index++)
            {
              'id':
                  '00000000-0000-4000-8000-${(index + (next ? 20 : 0)).toString().padLeft(12, '0')}',
              'title': 'Page row ${index + (next ? 20 : 0)}',
              'event_status': 'published',
              'member_role': 'participant',
              'membership_status': 'approved',
              'starts_at': '2099-01-01T10:00:00Z',
              'ends_at': '2099-01-01T12:00:00Z',
              'price_amount': 0,
            },
        ],
        'hasMore': !searching && !next,
        'nextCursor': !searching && !next ? 'fixture-cursor' : null,
      };
      return http.Response(jsonEncode({'data': data}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const DaziApp(home: MyActivitiesPage(token: 'fixture')),
      );
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (uri) => uri.queryParameters['cursor'] == 'fixture-cursor',
        ),
        isTrue,
      );
      await tester.enterText(find.byType(TextField).first, 'needle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['q'], 'needle');
      expect(requests.last.queryParameters['cursor'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => client);
  });
}
