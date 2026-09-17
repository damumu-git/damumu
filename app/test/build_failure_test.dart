import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/build_failure.dart';

void main() {
  testWidgets('build failure page hides diagnostics and retries', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: BuildFailure(
          title: '页面暂时无法显示',
          message: '请重试以重新打开页面。',
          retryLabel: '再试一次',
          onRetry: () => retried = true,
        ),
      ),
    );

    expect(find.text('页面暂时无法显示'), findsOneWidget);
    expect(find.textContaining('private-debug-detail'), findsNothing);
    await tester.tap(find.text('再试一次'));
    expect(retried, isTrue);
  });
}
