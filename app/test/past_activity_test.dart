import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaihandazi/main.dart';

EventItem event({DateTime? start, DateTime? end}) => EventItem(
  id: 101,
  emoji: '🌿',
  title: 'Activity',
  category: 'Outdoor',
  time: '12:00',
  area: 'Seoul',
  distance: '1 km',
  host: 'Host',
  hostScore: 5,
  joined: 1,
  capacity: 6,
  startsAt: start,
  endsAt: end,
);

void main() {
  test('expiry uses the end time; ongoing and undated events are not past', () {
    final now = DateTime.now();
    expect(event(end: now.subtract(const Duration(seconds: 1))).isPast, isTrue);
    expect(event(end: now).isPast, isTrue);
    expect(
      event(
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 1)),
      ).isPast,
      isFalse,
    );
    expect(event().isPast, isFalse);
  });

  testWidgets('past card is labelled and detail cannot accept registration', (
    tester,
  ) async {
    final past = event(end: DateTime.utc(2020));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCard(event: past, onTap: () {}),
        ),
      ),
    );
    expect(find.text('Past event'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          event: past,
          onChanged: () {},
          onOpenMyActivities: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Past event'), findsWidgets);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('立即参加'), findsNothing);
  });

  testWidgets('ongoing card does not display past badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventCard(
            event: event(
              start: DateTime.now().subtract(const Duration(hours: 1)),
              end: DateTime.now().add(const Duration(hours: 1)),
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('Past event'), findsNothing);
  });
}
