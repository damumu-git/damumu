import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/activity_text.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/event_service.dart';
import 'package:zaihandazi/l10n.dart';
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
    'discovery uses the small category cover and ignores the uploaded photo',
    (tester) async {
      await mount(
        tester,
        ({latitude, longitude, city, district, required limit, cursor}) async =>
            const ActivityPage(
              items: [
                {
                  'id': 'activity',
                  'title': 'Art class',
                  'capacity': 10,
                  'cover_category_code': 'culture',
                  'cover_subcategory_code': 'exhibition',
                  'cover_url': 'https://example.test/uploaded.jpg',
                },
              ],
              nextCursor: null,
              hasMore: false,
            ),
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(EventCard),
          matching: find.byType(Image),
        ),
      );
      expect(
        image.image,
        const AssetImage('assets/activity-covers/sub/exhibition.webp'),
      );
    },
  );

  test(
    'expiration uses midnight in Korea and retains ended activities today',
    () {
      final now = DateTime.utc(2026, 11, 6, 4);
      expect(expiredActivity(DateTime.utc(2026, 11, 5, 14, 59), now), isTrue);
      expect(expiredActivity(DateTime.utc(2026, 11, 5, 15), now), isFalse);
      expect(
        expiredActivity(now.subtract(const Duration(hours: 1)), now),
        isFalse,
      );
    },
  );

  testWidgets('activity cards switch to the selected translation', (
    tester,
  ) async {
    await mount(
      tester,
      ({latitude, longitude, city, district, required limit, cursor}) async =>
          const ActivityPage(
            items: [
              {
                'id': 'translated-activity',
                'title': '한강 산책',
                'description': '한강으로 가요',
                'category_name': '散步',
                'category_names': {'zh': '散步', 'en': 'Walking', 'ko': '산책'},
                'translations': {
                  'zh': {'title': '汉江散步'},
                  'en': {'title': 'Han River walk'},
                },
              },
              {
                'id': 'original-activity',
                'title': '서울 공원 산책',
                'description': '함께 산책해요',
                'category_name': '산책',
                'translations': <String, dynamic>{},
              },
            ],
            nextCursor: null,
            hasMore: false,
          ),
    );
    expect(find.text('汉江散步'), findsOneWidget);
    expect(find.text('한강 산책'), findsNothing);
    expect(find.text('서울 공원 산책'), findsOneWidget);
    tester
        .widget<AppLocaleScope>(find.byType(AppLocaleScope))
        .onChanged(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Han River walk'), findsOneWidget);
    expect(find.text('Walking'), findsOneWidget);
    expect(find.text('汉江散步'), findsNothing);
    expect(find.text('서울 공원 산책'), findsOneWidget);
  });

  testWidgets(
    'append retry keeps cursor and items, deduplicates UUID, stops at end',
    (tester) async {
      final calls = <String?>[];
      var fail = true;
      await mount(tester, ({
        latitude,
        longitude,
        city,
        district,
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

  testWidgets(
    'home search dismisses the keyboard on outside tap, search action, and tab switch',
    (tester) async {
      await mount(
        tester,
        ({latitude, longitude, city, district, required limit, cursor}) async =>
            page([]),
      );
      await tester.tap(find.byKey(const Key('main-nav-0')));
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('home-search-field'));
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text('A LITTLE COMPANY'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.showKeyboard(search);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.showKeyboard(search);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.byKey(const Key('main-nav-1')));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('refresh supersedes an in-flight next page', (tester) async {
    final pending = Completer<ActivityPage>();
    final calls = <String?>[];
    await mount(tester, ({
      latitude,
      longitude,
      city,
      district,
      required limit,
      cursor,
    }) {
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
