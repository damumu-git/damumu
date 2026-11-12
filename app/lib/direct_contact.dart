import 'package:flutter/material.dart';

import 'l10n.dart';
import 'social_service.dart';

typedef OpenDirectChat = void Function(String id, String nickname);

Future<String?> _prompt(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        var text = '';
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: TextField(
              maxLength: 500,
              maxLines: 4,
              onChanged: (value) => setState(() => text = value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr('cancel')),
              ),
              FilledButton(
                onPressed: text.isEmpty
                    ? null
                    : () => Navigator.pop(context, text),
                child: Text(context.tr('contactSend')),
              ),
            ],
          ),
        );
      },
    );

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> composeContact(
  BuildContext context,
  String token,
  String kind,
  String eventId, {
  String? userId,
}) async {
  final text = await _prompt(
    context,
    context.tr(kind == 'inquiry' ? 'contactInquiry' : 'contactApply'),
  );
  if (text == null || !context.mounted) return;
  try {
    await SocialService.sendContactRequest(
      token,
      kind,
      eventId,
      text,
      userId: userId,
    );
    if (context.mounted) _notice(context, context.tr('contactSent'));
  } catch (error) {
    if (context.mounted) _notice(context, '$error');
  }
}

class DirectContactActions extends StatefulWidget {
  const DirectContactActions({
    required this.token,
    required this.userId,
    required this.nickname,
    required this.onOpen,
    super.key,
  });

  final String token;
  final String userId;
  final String nickname;
  final OpenDirectChat onOpen;

  @override
  State<DirectContactActions> createState() => _DirectContactActionsState();
}

class _DirectContactActionsState extends State<DirectContactActions> {
  Map<String, dynamic>? _options;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await SocialService.contactOptions(
        widget.token,
        widget.userId,
      );
      if (mounted) setState(() => _options = options);
    } catch (_) {
      // Contact controls require a server eligibility response.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _notice(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (options == null) return const SizedBox.shrink();
    final following = options['following'] == true;
    final eventId = options['request_event_id'] as String?;
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await SocialService.followContact(
                    widget.token,
                    widget.userId,
                    !following,
                  );
                  await _load();
                }),
          child: Text(
            context.tr(following ? 'contactUnfollow' : 'contactFollow'),
          ),
        ),
        if (options['can_chat'] == true)
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final id = await SocialService.openDirectContact(
                      widget.token,
                      widget.userId,
                    );
                    if (mounted) widget.onOpen(id, widget.nickname);
                  }),
            child: Text(context.tr('contactMessage')),
          )
        else if (eventId != null)
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await composeContact(
                      context,
                      widget.token,
                      'attended',
                      eventId,
                      userId: widget.userId,
                    );
                    await _load();
                  }),
            child: Text(context.tr('contactApply')),
          ),
      ],
    );
  }
}

class ContactRequestsPage extends StatefulWidget {
  const ContactRequestsPage({
    required this.token,
    required this.onOpen,
    super.key,
  });

  final String token;
  final OpenDirectChat onOpen;

  @override
  State<ContactRequestsPage> createState() => _ContactRequestsPageState();
}

class _ContactRequestsPageState extends State<ContactRequestsPage> {
  List<Map<String, dynamic>>? _items;
  bool _allow = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await (
        SocialService.contactRequests(widget.token),
        SocialService.contactPreference(widget.token),
      ).wait;
      if (mounted) {
        setState(() {
          _items = results.$1;
          _allow = results.$2;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) _notice(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('contactRequests'))),
    body: _items == null && _error == null
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_error != null) Text(_error!),
                if (_items != null)
                  SwitchListTile(
                    title: Text(context.tr('contactPreference')),
                    value: _allow,
                    onChanged: _busy
                        ? null
                        : (value) => _run(
                            () => SocialService.setContactPreference(
                              widget.token,
                              value,
                            ),
                          ),
                  ),
                if (_items?.isEmpty == true) Text(context.tr('contactEmpty')),
                for (final item in _items ?? const <Map<String, dynamic>>[])
                  _card(item),
              ],
            ),
          ),
  );

  Widget _card(Map<String, dynamic> item) {
    final pending = item['status'] == 'pending';
    final incoming = item['incoming'] == true;
    final inquiry = item['kind'] == 'inquiry';
    final nickname = item['peer_nickname'] as String? ?? context.tr('profile');
    final peer = item['peer_id'] as String;
    final thread = item['conversation_id'] as String?;
    final status = pending
        ? context.tr(incoming ? 'contactPending' : 'contactSent')
        : context.tr(
            item['status'] == 'accepted' ? 'contactAccepted' : 'contactClosed',
          );
    Future<void> respond(bool accept) => _run(() async {
      final id = await SocialService.respondToContact(
        widget.token,
        item['id'] as String,
        accept,
      );
      if (id != null && mounted) widget.onOpen(id, nickname);
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nickname, style: Theme.of(context).textTheme.titleMedium),
            Text(
              [
                context.tr(inquiry ? 'contactInquiry' : 'contactApply'),
                if (item['event_title'] != null) item['event_title'],
                status,
              ].join(' · '),
            ),
            if (item['body'] is String) Text(item['body'] as String),
            if (pending && incoming)
              Wrap(
                spacing: 4,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => respond(true),
                    child: Text(
                      context.tr(inquiry ? 'contactReply' : 'contactAccept'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => respond(false),
                    child: Text(context.tr('contactDecline')),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final reason = await _prompt(
                              context,
                              context.tr('report'),
                            );
                            if (reason == null || !mounted) return;
                            await SocialService.reportContact(
                              widget.token,
                              peer,
                              reason,
                            );
                            if (mounted) {
                              _notice(context, context.tr('feedbackSubmitted'));
                            }
                          }),
                    child: Text(context.tr('report')),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () =>
                                SocialService.blockContact(widget.token, peer),
                          ),
                    child: Text(context.tr('contactBlock')),
                  ),
                ],
              )
            else if (thread != null)
              TextButton(
                onPressed: () => widget.onOpen(thread, nickname),
                child: Text(context.tr('contactMessage')),
              ),
          ],
        ),
      ),
    );
  }
}
