import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/feedback.dart';
import 'package:zaihandazi/feedback_model.dart';
import 'package:zaihandazi/main.dart';

void main() {
  for (final alreadySubmitted in [false, true]) {
    testWidgets(
      'user feedback locks after submit (existing: $alreadySubmitted)',
      (tester) async {
        var submissions = 0;
        final client = MockClient((request) async {
          expect(request.method, 'POST');
          submissions++;
          return alreadySubmitted
              ? http.Response(
                  '{"error":{"code":"user_feedback_already_submitted"}}',
                  409,
                )
              : http.Response('{"data":{}}', 200);
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: FeedbackActionGrid(
                  token: 'token',
                  eventId: 'event',
                  targetType: 'user',
                  targetUserId: 'peer',
                  initialEligibility: FeedbackEligibilityData(eligible: true),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(FeedbackActionCard).first);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ChoiceChip).first);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          final cards = tester.widgetList<FeedbackActionCard>(
            find.byType(FeedbackActionCard),
          );
          expect(cards.first.label, 'Feedback submitted');
          expect(cards.first.onTap, isNull);
          expect(cards.last.onTap, isNotNull);
          await tester.tap(find.byType(FeedbackActionCard).first);
          await tester.pumpAndSettle();
          expect(find.byType(FeedbackTagDialog), findsNothing);
          expect(submissions, 1);
        }, () => client);
      },
    );
  }

  testWidgets(
    'feedback actions are square, spaced, and wrap on narrow screens',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(240, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackActionGrid(
              token: 'token',
              eventId: 'event',
              targetType: 'activity',
              initialEligibility: const FeedbackEligibilityData(eligible: true),
              onPublishSimilar: () {},
            ),
          ),
        ),
      );
      final cards = find.byType(FeedbackActionCard);
      expect(cards, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(cards.at(i)), const Size(104, 104));
      }
      final first = tester.getRect(cards.at(0));
      final second = tester.getRect(cards.at(1));
      final third = tester.getRect(cards.at(2));
      expect(second.left - first.right, greaterThanOrEqualTo(12));
      expect(third.top - first.bottom, greaterThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile feedback activates only with verified event context', (
    tester,
  ) async {
    final auth = AuthController()
      ..token = 'test-token'
      ..user = const AuthUser(
        id: 'viewer',
        nickname: 'Viewer',
        email: 'viewer@example.com',
        avatarUrl: 'system:sprout',
      );
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['eventId'], 'event-1');
      return http.Response(
        jsonEncode({
          'data': {
            'id': 'target',
            'nickname': 'Target',
            'like_count': 7,
            'positive_tags': [
              {'tag_code': 'reliable', 'count': 3},
            ],
            'feedback_eligible': true,
            'viewer_like_tag': null,
            'viewer_report_tag': null,
          },
        }),
        200,
      );
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(
        DaziApp(
          home: AuthScope(
            controller: auth,
            child: const PublicUserProfilePage(
              userId: 'target',
              eventId: 'event-1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('♥ 获赞 7'), findsOneWidget);
      final tag = find.widgetWithText(ActionChip, '值得信赖 ×3');
      expect(tag, findsOneWidget);
      final position = tester.getTopLeft(tag);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getTopLeft(tag).dy, isNot(position.dy));
      await tester.tap(tag);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('来自活动后的参与者评价'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('喜欢'), findsOneWidget);
      expect(find.text('举报'), findsOneWidget);
    }, () => client);
  });

  testWidgets('risk signal appears on activity cards at API threshold result', (
    tester,
  ) async {
    final event = EventItem(
      id: 1,
      emoji: '🎯',
      title: 'Reported activity',
      category: 'Social',
      time: '12:00',
      area: 'Seoul',
      distance: '1 km',
      host: 'Host',
      hostScore: 4,
      joined: 2,
      capacity: 5,
      organizerRiskTag: 'unexpected_costs',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthScope(
            controller: AuthController(),
            child: EventCard(event: event, onTap: () {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('Unexpected costs'), findsOneWidget);
  });
}
