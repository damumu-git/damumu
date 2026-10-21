import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zaihandazi/auth.dart';
import 'package:zaihandazi/external_processing.dart';
import 'package:zaihandazi/privacy_retention.dart';
import 'package:zaihandazi/social_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'retention uses calendar months, including short months and leap years',
    () {
      expect(
        privacyRetentionCutoff(DateTime.utc(2026, 5, 31)),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        privacyRetentionCutoff(DateTime.utc(2024, 5, 31)),
        DateTime.utc(2024, 2, 29),
      );
      expect(
        privacyRetentionCutoff(DateTime.utc(2026, 1, 15)),
        DateTime.utc(2025, 10, 15),
      );
    },
  );

  test(
    'startup removes expired and corrupt local chat data from storage',
    () async {
      final now = DateTime.now().toUtc();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'chat_cache_user_chat',
        jsonEncode([
          {
            'id': 'old',
            'created_at': now
                .subtract(const Duration(days: 200))
                .toIso8601String(),
          },
          {'id': 'recent', 'created_at': now.toIso8601String()},
        ]),
      );
      await preferences.setString('chat_pending_user_chat', 'corrupt');
      await SocialService.purgeExpiredLocalMessages();
      final stored =
          jsonDecode(preferences.getString('chat_cache_user_chat')!) as List;
      expect(stored.single['id'], 'recent');
      expect(preferences.containsKey('chat_pending_user_chat'), isFalse);
    },
  );

  test(
    'registration sends explicit age and current notice acknowledgements',
    () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['ageConfirmed'], isTrue);
        expect(body['privacyAcknowledged'], isTrue);
        expect(body['privacyVersion'], '2026-10-21');
        return http.Response('{"data":{}}', 201);
      });
      await http.runWithClient(
        () => AuthApi.register(
          'name',
          'test@example.test',
          'test12345',
          null,
          ageConfirmed: true,
          privacyAcknowledged: true,
        ),
        () => client,
      );
    },
  );

  test(
    'external processing remains blocked before release disclosure approval',
    () async {
      await (await SharedPreferences.getInstance()).setBool(
        'external_push_20261021',
        true,
      );
      expect(await externalProcessingAllowed('push'), isFalse);
      expect(await externalProcessingAllowed('geocoding'), isFalse);
    },
  );

  testWidgets(
    'registration presents separate unchecked age and privacy confirmations',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: AuthPage(avatarLoader: (_) async => const [])),
      );
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      final checkboxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(checkboxes.length, 2);
      expect(checkboxes.every((item) => item.value == false), isTrue);
    },
  );

  testWidgets(
    'image credentials are restricted to private media on the configured API origin',
    (tester) async {
      final auth = AuthController()..token = 'test-token';
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                expect(
                  privateImageHeaders(context, '/uploads/messages/a/image.jpg'),
                  {'Authorization': 'Bearer test-token'},
                );
                expect(
                  privateImageHeaders(
                    context,
                    'https://other.example/uploads/messages/a/image.jpg',
                  ),
                  isNull,
                );
                expect(
                  privateImageHeaders(
                    context,
                    '/uploads/system-avatars/test.jpg',
                  ),
                  isNull,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
