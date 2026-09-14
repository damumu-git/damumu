import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/event_service.dart';

void main() {
  test('requests successive pages with the same location', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      final cursor = request.url.queryParameters['cursor'];
      expect(request.url.path, '/api/v1/activities');
      return http.Response(
        jsonEncode({
          'data': {
            'items': cursor == null
                ? List.generate(20, (i) => {'id': '$i'})
                : [],
            'nextCursor': cursor == null ? 'next-page' : null,
            'hasMore': cursor == null,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      final first = await EventService.list(latitude: 37.5, longitude: 127);
      final last = await EventService.list(
        latitude: 37.5,
        longitude: 127,
        cursor: first.nextCursor,
      );
      expect(first.items, hasLength(20));
      expect(last.items, isEmpty);
    }, () => client);
    expect(requests.map((uri) => uri.queryParameters['cursor']), [
      null,
      'next-page',
    ]);
    for (final uri in requests) {
      expect(uri.queryParameters['limit'], '20');
      expect(uri.queryParameters['latitude'], '37.5');
      expect(uri.queryParameters['longitude'], '127.0');
    }
  });

  test('page failure is safe and can be retried at the same cursor', () async {
    var calls = 0;
    final client = MockClient((request) async {
      expect(request.url.queryParameters['cursor'], 'next-page');
      calls++;
      if (calls == 1) {
        return http.Response('<html>internal failure</html>', 500);
      }
      return http.Response(
        jsonEncode({
          'data': {
            'items': [
              {'id': 'next'},
            ],
            'nextCursor': null,
            'hasMore': false,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await expectLater(
        EventService.list(cursor: 'next-page'),
        throwsA(isA<EventServiceException>()),
      );
      expect((await EventService.list(cursor: 'next-page')).items, [
        {'id': 'next'},
      ]);
    }, () => client);
    expect(calls, 2);
  });
}
