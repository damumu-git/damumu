import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/community_groups.dart';

void main() {
  testWidgets(
    'group approval requests update the detail and can be withdrawn',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 840));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = AuthController()
        ..token = 'test-token'
        ..user = const AuthUser(
          id: 'viewer',
          nickname: 'Viewer',
          email: 'viewer@example.test',
        );
      var pending = false;
      final requests = <String>[];
      final item = {
        'id': 'group-1',
        'owner_id': 'owner',
        'title': 'Friday walkers',
        'description': 'Walk together in Seoul.',
        'member_count': 1,
        'capacity': 12,
        'join_mode': 'approval',
        'categories': ['Outdoors'],
      };
      final client = MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path.endsWith('/membership')) {
          expect(request.headers['authorization'], 'Bearer test-token');
          pending = request.method == 'PUT';
        }
        final Object data = path.endsWith('/groups')
            ? [item]
            : {
                'item': {...item, 'pending': pending, 'joined': false},
                'events': [],
                'members': [],
                'applications': [],
              };
        return http.Response(jsonEncode({'data': data}), 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          AuthScope(
            controller: auth,
            child: MaterialApp(
              home: CommunityGroupsPage(
                openActivity: (_, _) {},
                openPerson: (_, _) {},
                openChat: (_, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Friday walkers'));
        await tester.pumpAndSettle();
        expect(requests, contains('GET /api/v1/web/groups/group-1'));
        expect(find.text('Open to join'), findsNothing);
        expect(find.textContaining('Owner approval required'), findsOneWidget);
        expect(find.text('Group chat'), findsNothing);
        await tester.tap(find.text('Request to join'));
        await tester.pumpAndSettle();
        expect(find.text('Withdraw request'), findsOneWidget);
        expect(
          find.text('Your request is awaiting the group owner’s approval.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Withdraw request'));
        await tester.pumpAndSettle();
        expect(find.text('Request to join'), findsOneWidget);
        expect(
          requests,
          containsAllInOrder([
            'PUT /api/v1/web/groups/group-1/membership',
            'DELETE /api/v1/web/groups/group-1/membership',
          ]),
        );
      }, () => client);
    },
  );
}
