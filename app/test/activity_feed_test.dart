import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/event_service.dart';
import 'package:zaihandazi/main.dart';

ActivityPage page(List<String> ids, {String? next}) => ActivityPage(
  items: ids
      .map(
        (id) => <String, dynamic>{
          'id': id,
          'title': id,
          'capacity': 10,
          'distance_meters': 100,
        },
      )
      .toList(),
  nextCursor: next,
  hasMore: next != null,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(WidgetTester tester, ActivityPageLoader loader) async {
    final auth = AuthController()
      ..user = const AuthUser(
        id: 'test-user',
        nickname: 'Tester',
        email: 'test@example.com',
        avatarUrl: 'system:sprout',
      );
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DaziApp(
        home: AuthScope(
          controller: auth,
          child: AppShell(eventLoader: loader, loadRemoteEvents: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('main-nav-1')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'append retry keeps cursor and items, deduplicates UUID, stops at end',
    (tester) async {
      final calls = <String?>[];
      var fail = true;
      await mount(tester, ({
        latitude,
        longitude,
        required limit,
        cursor,
      }) async {
        calls.add(cursor);
        if (cursor == null) return page(['first'], next: 'c1');
        if (fail) {
          fail = false;
          throw Exception('private failure');
        }
        return page(['first', 'second']);
      });
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('private failure'), findsNothing);
      await tester.tap(find.text('再试一次'));
      await tester.pumpAndSettle();
      expect(calls, [null, 'c1', 'c1']);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
      expect(find.text('已加载全部活动'), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
    },
  );

  testWidgets('refresh supersedes an in-flight next page', (tester) async {
    final pending = Completer<ActivityPage>();
    final calls = <String?>[];
    await mount(tester, ({latitude, longitude, required limit, cursor}) {
      calls.add(cursor);
      if (cursor != null) return pending.future;
      return Future.value(
        calls.length == 1 ? page(['old'], next: 'c1') : page(['fresh']),
      );
    });
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(find.text('加载更多'), findsNothing);
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('fresh'), findsOneWidget);
    pending.complete(page(['stale']));
    await tester.pumpAndSettle();
    expect(calls, [null, 'c1', null]);
    expect(find.text('stale'), findsNothing);
    expect(find.text('old'), findsNothing);
    expect(find.text('fresh'), findsOneWidget);
  });
}
