import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/activity_series.dart';
import 'package:zaihandazi/auth.dart';

void main() {
  testWidgets('series page saves a subscription and opens the next activity', (
    tester,
  ) async {
    final auth = AuthController()..token = 'fixture';
    Map<String, dynamic>? membership;
    String? opened;
    final client = MockClient((request) async {
      if (request.method == 'PUT') {
        expect(request.url.path, endsWith('/series/fixture/membership'));
        expect(request.headers['Authorization'], 'Bearer fixture');
        membership = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"data":{}}', 200);
      }
      expect(request.url.path, endsWith('/series/damu-weekend'));
      return http.Response(
        jsonEncode({
          'data': {
            'item': {
              'id': 'fixture',
              'title': 'Damu Weekend',
              'description': 'Activities nearby',
              'interest_count': 0,
              'subscribed': membership?['subscribed'] ?? false,
            },
            'events': [
              {'id': 'next', 'title': 'Weekend walk', 'ended': false},
            ],
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScope(
            controller: auth,
            child: ActivitySeriesPage(
              seriesKey: 'damu-weekend',
              openEvent: (_, id) => opened = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Damu Weekend'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(membership, {'subscribed': true, 'interestSlot': null});
      await tester.ensureVisible(find.text('Weekend walk'));
      await tester.tap(find.text('Weekend walk'));
      expect(opened, 'next');
    }, () => client);
  });
}
