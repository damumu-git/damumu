import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/l10n.dart';
import 'package:zaihandazi/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget authenticatedApp() {
    final auth = AuthController()
      ..user = const AuthUser(
        id: 'test-user',
        nickname: '林夏',
        email: 'linxia@example.com',
        avatarUrl: 'system:sprout',
      );
    return DaziApp(
      home: AuthScope(
        controller: auth,
        child: AppShell(initialEvents: demoEvents, loadRemoteEvents: false),
      ),
    );
  }

  testWidgets('首页可以进入活动详情并完成报名', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(authenticatedApp());
    await tester.pumpAndSettle();

    expect(find.text('今天，找个搭子'), findsOneWidget);
    expect(find.text('汉江日落野餐局'), findsOneWidget);

    await tester.tap(find.text('汉江日落野餐局'));
    await tester.pumpAndSettle();

    expect(find.text('活动介绍'), findsOneWidget);
    expect(find.text('立即参加'), findsOneWidget);

    await tester.tap(find.text('立即参加'));
    await tester.pumpAndSettle();

    expect(find.text('参加成功！'), findsOneWidget);
    expect(find.text('活动群聊已解锁，可在「消息」中查看'), findsOneWidget);
  });

  testWidgets('自己发布的活动显示身份且不出现报名按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final ownedEvent = EventItem(
      id: 99,
      emoji: '🌿',
      title: '我发布的测试活动',
      category: '户外',
      time: '今天 18:30',
      area: '首尔',
      distance: '1.0 km',
      host: '林夏',
      hostScore: 4.8,
      joined: 1,
      capacity: 8,
      approval: true,
      isOwned: true,
    );
    var openedMyActivities = false;

    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          event: ownedEvent,
          onChanged: () {},
          onOpenMyActivities: () => openedMyActivities = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我发布的'), findsOneWidget);
    expect(find.text('查看我的活动'), findsOneWidget);
    expect(find.text('申请参加'), findsNothing);
    expect(find.text('立即参加'), findsNothing);

    await tester.tap(find.text('查看我的活动'));
    expect(openedMyActivities, isTrue);
  });

  testWidgets('五个一级入口均可访问', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(authenticatedApp());
    await tester.pumpAndSettle();

    for (final index in [1, 2, 3, 4]) {
      await tester.tap(find.byKey(Key('main-nav-$index')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('main-nav-$index')), findsOneWidget);
    }
  });

  testWidgets('首页可以搜索并组合筛选活动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(authenticatedApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('home-search-field')), '延南洞');
    await tester.pumpAndSettle();
    expect(find.text('延南洞韩语口语交换'), findsOneWidget);
    expect(find.text('汉江日落野餐局'), findsNothing);

    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到符合条件的活动'), findsOneWidget);

    await tester.tap(find.text('清除全部筛选'));
    await tester.pumpAndSettle();
    expect(find.text('汉江日落野餐局'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('周六清晨北汉山轻徒步'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('周六清晨北汉山轻徒步'), findsOneWidget);
  });

  testWidgets('可以恢复英文和韩文界面语言', (tester) async {
    SharedPreferences.setMockInitialValues({'app_locale': 'ko'});
    await tester.pumpWidget(
      DaziApp(home: AuthPage(avatarLoader: (_) async => const [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('다지 계정 만들기'), findsNothing);
    expect(find.text('다시 오신 것을 환영해요'), findsOneWidget);

    final scope = tester.widget<AppLocaleScope>(find.byType(AppLocaleScope));
    scope.onChanged(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
