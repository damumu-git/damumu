import 'package:flutter/material.dart';

import 'activity_series.dart';
import 'l10n.dart';
import 'social_service.dart';
import 'user_avatar_image.dart';

Future<String?> friendNote(BuildContext context) {
  var note = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('friendAdd')),
      content: TextField(
        maxLength: 200,
        maxLines: 3,
        decoration: InputDecoration(labelText: context.tr('friendNote')),
        onChanged: (value) => note = value,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, note),
          child: Text(context.tr('contactSend')),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, String key) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.tr(key)),
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
    ) ??
    false;

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    required this.token,
    required this.onOpen,
    this.requests = false,
    super.key,
  });

  final String token;
  final bool requests;
  final void Function(String id, String nickname) onOpen;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _query = '';
  bool _allow = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await SocialService.friends(
        widget.token,
        requests: widget.requests,
      );
      final allow =
          !widget.requests ||
          await SocialService.friendPreference(widget.token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _allow = allow;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    bool reload = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (reload && mounted) await _load();
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
  Widget build(BuildContext context) {
    final items = _items;
    final results = items
        ?.where((item) => _name(item).toLowerCase().contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(widget.requests ? 'friendRequests' : 'friendList'),
        ),
      ),
      body: items == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error case final error?)
                    ListTile(
                      title: Text(error),
                      onTap: _load,
                      trailing: const Icon(Icons.refresh),
                    ),
                  if (widget.requests && items != null) ...[
                    SwitchListTile(
                      title: Text(context.tr('friendPreference')),
                      value: _allow,
                      onChanged: _busy
                          ? null
                          : (value) => _run(
                              () => SocialService.setFriendPreference(
                                widget.token,
                                value,
                              ),
                            ),
                    ),
                    for (final incoming in [true, false]) ...[
                      ListTile(
                        title: Text(
                          context.tr(
                            incoming ? 'friendIncoming' : 'friendOutgoing',
                          ),
                        ),
                      ),
                      if (!items.any((item) => item['incoming'] == incoming))
                        ListTile(title: Text(context.tr('friendNoRequests'))),
                      for (final item in items.where(
                        (item) => item['incoming'] == incoming,
                      ))
                        _requestRow(item),
                    ],
                  ] else if (results != null) ...[
                    TextField(
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        labelText: context.tr('friendSearch'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    if (results.isEmpty)
                      ListTile(title: Text(context.tr('friendNone'))),
                    for (final item in results) _friendRow(item),
                  ],
                ],
              ),
            ),
    );
  }

  String _name(Map<String, dynamic> item) =>
      (item['nickname'] ?? item['peer_nickname']) as String? ??
      context.tr('profile');

  Widget _avatar(Map<String, dynamic> item) => UserAvatarImage(
    nickname: _name(item),
    radius: 20,
    avatarUrl: (item['avatar_url'] ?? item['peer_avatar']) as String?,
  );

  Widget _friendRow(Map<String, dynamic> item) {
    final id = item['id'] as String;
    return ListTile(
      leading: _avatar(item),
      title: Text(_name(item)),
      onTap: _busy
          ? null
          : () => _run(() async {
              final conversation = await SocialService.openDirectContact(
                widget.token,
                id,
              );
              if (mounted) widget.onOpen(conversation, _name(item));
            }, reload: false),
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        onSelected: (_) async {
          if (await _confirm(context, 'friendRemoveConfirm') && mounted) {
            await _run(() => SocialService.removeFriend(widget.token, id));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'remove',
            child: Text(context.tr('friendRemove')),
          ),
        ],
      ),
    );
  }

  Widget _requestRow(Map<String, dynamic> item) {
    final incoming = item['incoming'] == true;
    final status = item['status'];
    final key = switch (status) {
      'pending' => incoming ? 'contactPending' : 'contactSent',
      'accepted' => 'contactAccepted',
      'withdrawn' => 'friendWithdrawn',
      _ => 'contactClosed',
    };
    Widget decide(String label, String decision) => TextButton(
      onPressed: _busy
          ? null
          : () => _run(
              () => SocialService.respondToFriend(
                widget.token,
                item['id'] as String,
                decision,
              ),
            ),
      child: Text(context.tr(label)),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: _avatar(item),
              title: Text(_name(item)),
              subtitle: Text(
                [
                  context.tr(key),
                  if (item['body'] case final String note) note,
                ].join('\n'),
              ),
            ),
            if (status == 'pending')
              Wrap(
                children: [
                  if (incoming) ...[
                    decide('contactAccept', 'accepted'),
                    decide('friendIgnore', 'ignored'),
                    decide('contactDecline', 'declined'),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(
                                    context,
                                    'friendBlockConfirm',
                                  ) &&
                                  mounted) {
                                await _run(
                                  () => SocialService.blockContact(
                                    widget.token,
                                    item['peer_id'] as String,
                                  ),
                                );
                              }
                            },
                      child: Text(context.tr('contactBlock')),
                    ),
                  ] else
                    decide('friendWithdraw', 'withdrawn'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ShareActivityDialog extends StatefulWidget {
  const ShareActivityDialog({super.key});

  @override
  State<ShareActivityDialog> createState() => _ShareActivityDialogState();
}

class _ShareActivityDialogState extends State<ShareActivityDialog> {
  final _query = TextEditingController();
  List<SeriesRow> _items = [];
  bool _loading = true;
  String? _error;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final id = ++_searchId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ActivitySeriesService.request(
                '/activities?${Uri(queryParameters: {'q': _query.text.trim(), 'limit': '8'}).query}',
              )
              as SeriesRow;
      if (mounted && id == _searchId) {
        setState(() => _items = ActivitySeriesService.rows(result['items']));
      }
    } catch (error) {
      if (mounted && id == _searchId) setState(() => _error = '$error');
    } finally {
      if (mounted && id == _searchId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('friendShareActivity')),
    content: SizedBox(
      width: 380,
      height: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _query,
            maxLength: 100,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: context.tr('friendActivitySearch'),
              suffixIcon: IconButton(
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator()
          else if (_error case final error?)
            Text(error)
          else if (_items.isEmpty)
            Text(context.tr('friendNoActivities'))
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in _items)
                    ListTile(
                      title: Text(item['title'] as String),
                      trailing: const Icon(Icons.send_outlined),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
    ],
  );
}
