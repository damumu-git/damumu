import 'package:flutter/material.dart';

import 'auth.dart';
import 'l10n.dart';
import 'social_service.dart';

class SessionDevicesPage extends StatefulWidget {
  const SessionDevicesPage({
    required this.token,
    required this.onSignOut,
    super.key,
  });
  final String token;
  final Future<void> Function() onSignOut;

  @override
  State<SessionDevicesPage> createState() => _SessionDevicesPageState();
}

class _SessionDevicesPageState extends State<SessionDevicesPage> {
  late Future<List<Map<String, dynamic>>> _sessions =
      SocialService.loginSessions(widget.token);
  bool _busy = false;

  Future<void> _revoke(Map<String, dynamic>? session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          context.tr(
            session == null ? 'sessionsEndAllConfirm' : 'sessionsEndConfirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('friendConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      if (session == null) {
        await AuthApi.endSession(widget.token, all: true);
      } else {
        await SocialService.endLoginSession(
          widget.token,
          session['id'] as String,
        );
      }
      if (session == null || session['current'] == true) {
        await widget.onSignOut();
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => _sessions = SocialService.loginSessions(widget.token));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('sessionsTitle'))),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _sessions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(
                () => _sessions = SocialService.loginSessions(widget.token),
              ),
              child: Text(context.tr('reload')),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final session in snapshot.data!)
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(
                  context.tr(
                    session['current'] == true
                        ? 'sessionsCurrent'
                        : 'sessionsOther',
                  ),
                ),
                subtitle: Text(
                  DateTime.tryParse(
                        '${session['created_at']}',
                      )?.toLocal().toString().split('.').first ??
                      '',
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _revoke(session),
                  child: Text(context.tr('sessionsEnd')),
                ),
              ),
            OutlinedButton(
              onPressed: _busy ? null : () => _revoke(null),
              child: Text(context.tr('sessionsEndAll')),
            ),
          ],
        );
      },
    ),
  );
}
