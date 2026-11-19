import 'package:flutter/material.dart';

import 'activity_series.dart';
import 'l10n.dart';
import 'build_failure.dart';

class RecurringPlansPage extends StatefulWidget {
  const RecurringPlansPage({
    required this.token,
    required this.openEvent,
    super.key,
  });
  final String token;
  final Future<void> Function(BuildContext, String) openEvent;

  @override
  State<RecurringPlansPage> createState() => _RecurringPlansPageState();
}

class _RecurringPlansPageState extends State<RecurringPlansPage> {
  late Future<List<SeriesRow>> _future = _load();
  bool _busy = false;

  Future<List<SeriesRow>> _load() async => ActivitySeriesService.rows(
    await ActivitySeriesService.request(
      '/me/recurring-events',
      token: widget.token,
    ),
  );

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _change(SeriesRow plan, {int? occurrence}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (occurrence == null) {
        await ActivitySeriesService.request(
          '/recurring-events/${plan['id']}',
          token: widget.token,
          method: 'PATCH',
          data: {'paused': plan['paused'] != true},
        );
      } else {
        final result = await ActivitySeriesService.request(
          '/recurring-events/${plan['id']}/occurrences/$occurrence',
          token: widget.token,
          method: 'POST',
          data: {},
        );
        if (!mounted) return;
        await widget.openEvent(context, '${result['id']}');
      }
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(dynamic value) {
    final date = DateTime.parse('$value').toUtc().add(const Duration(hours: 9));
    String two(int number) => number.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('recurringPlans'))),
    body: FutureBuilder<List<SeriesRow>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return BuildFailure(
            title: context.tr('loadErrorTitle'),
            message: context.tr('loadErrorMessage'),
            retryLabel: context.tr('refresh'),
            onRetry: _refresh,
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final plans = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.tr('recurringHelp')),
              if (plans.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(context.tr('recurringEmpty')),
                ),
              for (final plan in plans)
                Card(
                  child: ExpansionTile(
                    title: Text('${plan['title']}'),
                    subtitle: Text(
                      context.tr(
                        plan['completed'] == true
                            ? 'recurringCompleted'
                            : plan['paused'] == true
                            ? 'recurringPaused'
                            : 'recurringActive',
                      ),
                    ),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _change(plan),
                        child: Text(
                          context.tr(
                            plan['paused'] == true
                                ? 'recurringResume'
                                : 'recurringPause',
                          ),
                        ),
                      ),
                      for (final slot in ActivitySeriesService.rows(
                        plan['occurrences'],
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_time(slot['startsAt'])),
                          subtitle: Text(_time(slot['endsAt'])),
                          trailing: slot['eventId'] != null
                              ? TextButton(
                                  onPressed: () => widget.openEvent(
                                    context,
                                    '${slot['eventId']}',
                                  ),
                                  child: Text(
                                    context.tr(
                                      slot['status'] == 'cancelled'
                                          ? 'eventCancelled'
                                          : 'recurringView',
                                    ),
                                  ),
                                )
                              : slot['canPublish'] == true
                              ? FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _change(
                                          plan,
                                          occurrence: (slot['index'] as num)
                                              .toInt(),
                                        ),
                                  child: Text(context.tr('recurringPublish')),
                                )
                              : Text(
                                  context.tr(
                                    DateTime.parse('${slot['startsAt']}')
                                            .isBefore(DateTime.now())
                                        ? 'pastActivity'
                                        : 'recurringWindow',
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
