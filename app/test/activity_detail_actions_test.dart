import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  for (final (membership, chatAccess, eligible) in [
    ('applied', false, false),
    ('approved', true, false),
    ('attended', true, true),
    ('attended', false, true),
  ]) {
    testWidgets(
      'detail follows chat and feedback permissions for $membership ($chatAccess)',
      (tester) async {
        final auth = AuthController()
          ..token = 'test-token'
          ..user = const AuthUser(
            id: 'member',
            nickname: 'Member',
            email: 'member@example.test',
          );
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/story')) {
            return http.Response('{"data":{}}', 200);
          }
          expect(request.url.path, endsWith('/events/sample'));
          return http.Response(
            jsonEncode({
              'data': {
                'item': {
                  'status': eligible ? 'completed' : 'published',
                  'visibility': 'public',
                  'viewer_membership_status': membership,
                  'viewer_can_open_chat': chatAccess,
                  'organizer_user_id': 'host',
                },
                'members': [],
                'feedback': {'eligible': eligible},
              },
            }),
            200,
          );
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            AuthScope(
              controller: auth,
              child: MaterialApp(
                home: EventDetailPage(
                  event: EventItem(
                    id: 1,
                    apiId: 'sample',
                    emoji: '⚽',
                    title: 'Football',
                    category: 'Sports',
                    time: '10:00',
                    area: 'Seoul',
                    distance: '',
                    host: 'Host',
                    hostScore: 0,
                    joined: 1,
                    capacity: 6,
                  ),
                  onChanged: () {},
                  onOpenMyActivities: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('open-activity-chat')),
            chatAccess ? findsOneWidget : findsNothing,
          );
          expect(
            find.byIcon(Icons.favorite_border),
            eligible ? findsOneWidget : findsNothing,
          );
          expect(find.byIcon(Icons.bookmark_border), findsNothing);
          expect(find.byIcon(Icons.bookmark_outline), findsNothing);
        }, () => client);
      },
    );
  }
}
