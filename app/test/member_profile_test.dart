import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/member_profile.dart';

void main() {
  testWidgets('editing a bio preserves a private home region', (tester) async {
    Map<String, dynamic>? update;
    final client = MockClient((request) async {
      Object result = {};
      if (request.url.path.endsWith('/regions')) {
        result = [
          {
            'code': 'SEOUL',
            'level': 1,
            'name_zh_cn': '首尔',
            'name_en_us': 'Seoul',
          },
          {
            'code': 'MAPO',
            'level': 2,
            'parent_code': 'SEOUL',
            'name_zh_cn': '麻浦区',
            'name_en_us': 'Mapo District',
          },
        ];
      } else {
        expect(request.url.path, endsWith('/me/member-profile'));
        expect(request.headers['Authorization'], 'Bearer fixture');
        if (request.method == 'PUT') {
          update = jsonDecode(request.body) as Map<String, dynamic>;
        } else {
          result = {
            'bio': 'Before',
            'home_region_code': 'MAPO',
            'show_home_region': false,
          };
        }
      }
      return http.Response(
        jsonEncode({'data': result}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: MemberProfileEditor(token: 'fixture')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<DropdownButton<String>>(
              find.byType(DropdownButton<String>),
            )
            .map((picker) => picker.value),
        ['SEOUL', 'MAPO'],
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'After');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(update, {
        'bio': 'After',
        'homeRegionCode': 'MAPO',
        'showHomeRegion': false,
      });
    }, () => client);
  });

  testWidgets('following list opens the profile and supports unfollowing', (
    tester,
  ) async {
    String? opened;
    var followed = true;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer fixture');
      if (request.method == 'DELETE') {
        expect(request.url.path, endsWith('/web/follows/host'));
        followed = false;
        return http.Response('{"data":{}}', 200);
      }
      expect(request.url.path, endsWith('/me/following'));
      return http.Response(
        jsonEncode({
          'data': {
            'items': [
              if (followed) {'id': 'host', 'nickname': 'Host', 'mutual': true},
            ],
            'hasMore': false,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: MemberLibraryPage(
            token: 'fixture',
            following: true,
            openPerson: (_, id) async {
              opened = id;
            },
            openActivity: (_, _) async {},
            activityThumbnail: (_, _) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mutual follow'), findsOneWidget);
      await tester.tap(find.text('Host'));
      await tester.pumpAndSettle();
      expect(opened, 'host');
      await tester.tap(find.byIcon(Icons.person_remove_outlined));
      await tester.pumpAndSettle();
      expect(followed, isFalse);
      expect(find.text('Host'), findsNothing);
    }, () => client);
  });
}
