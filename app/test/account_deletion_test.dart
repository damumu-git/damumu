import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/main.dart';

void main() {
  testWidgets(
    'account deletion checks email and permits cancelling without submission',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthController()
        ..user = const AuthUser(
          id: 'test',
          nickname: 'Test',
          email: 'owner@example.com',
        )
        ..token = 'test-token';
      await tester.pumpWidget(
        DaziApp(
          home: AuthScope(
            controller: auth,
            child: const Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('账号管理'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'other@example.com');
      await tester.tap(find.text('确认删除账号'));
      await tester.pumpAndSettle();
      expect(find.text('请输入当前账号的注册邮箱'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'owner@example.com');
      await tester.enterText(find.byType(TextField).last, 'example-password');
      await tester.tap(find.text('确认删除账号'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(auth.user?.email, 'owner@example.com');
      expect(auth.token, 'test-token');
    },
  );
}
