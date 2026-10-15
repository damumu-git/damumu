import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/event_service.dart';

void main() {
  test('publisher beginner-friendly declaration is sent to the API', () async {
    final received = <bool>[];
    final client = MockClient((request) async {
      final claimed =
          (jsonDecode(request.body) as Map<String, dynamic>)['beginnerFriendly']
              as bool;
      received.add(claimed);
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'event-id',
            'beginnerFriendly': claimed,
            'beginnerFriendlyVerified': claimed,
          },
        }),
        200,
      );
    });

    final results = <({bool friendly, bool verified})>[];
    await http.runWithClient(() async {
      for (final beginnerFriendly in [true, false]) {
        final result = await EventService.create(
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
          approvalRequired: true,
          beginnerFriendly: beginnerFriendly,
        );
        results.add((
          friendly: result.beginnerFriendly,
          verified: result.beginnerFriendlyVerified,
        ));
      }
    }, () => client);

    expect(received, [true, false]);
    expect(results, [
      (friendly: true, verified: true),
      (friendly: false, verified: false),
    ]);
  });
}
