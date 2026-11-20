import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'session_transport.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'activity_series.dart';
import 'auth.dart';
import 'event_cover_image.dart';
import 'l10n.dart';
import 'member_level_guide.dart';

const _api = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.damumu.com/api/v1',
);
const _groups = '/web/groups';

typedef OpenGroupChat = void Function(BuildContext context, SeriesRow group);

class CommunityGroupsPage extends StatefulWidget {
  const CommunityGroupsPage({
    required this.openActivity,
    required this.openPerson,
    required this.openChat,
    super.key,
  });

  final OpenSeriesEvent openActivity;
  final OpenSeriesEvent openPerson;
  final OpenGroupChat openChat;

  @override
  State<CommunityGroupsPage> createState() => _CommunityGroupsPageState();
}

class _CommunityGroupsPageState extends State<CommunityGroupsPage> {
  late Future<dynamic> _groupsFuture = ActivitySeriesService.request(_groups);

  void _reload() =>
      setState(() => _groupsFuture = ActivitySeriesService.request(_groups));

  Future<void> _open(String id) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _GroupDetail(id: id, actions: widget),
    ),
  );

  Future<void> _create() async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _GroupEditor(token: token)),
    );
    if (!mounted || id == null) return;
    _reload();
    await _open(id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('communityGroups'))),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: Text(context.tr('groupCreate')),
    ),
    body: FutureBuilder<dynamic>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _GroupLoadError(snapshot.error, _reload);
        }
        final items = ActivitySeriesService.rows(snapshot.data);
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _groupsFuture;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.isEmpty ? 1 : items.length,
            itemBuilder: (context, index) {
              if (items.isEmpty) return _EmptyGroupText('groupEmpty');
              final item = items[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    await _open(item['id'] as String);
                    if (mounted) _reload();
                  },
                  child: _GroupSummary(item: item, detail: false),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

class _GroupDetail extends StatefulWidget {
  const _GroupDetail({required this.id, required this.actions});
  final String id;
  final CommunityGroupsPage actions;

  @override
  State<_GroupDetail> createState() => _GroupDetailState();
}

class _GroupDetailState extends State<_GroupDetail> {
  Future<dynamic>? _result;
  String? _loadedToken;
  bool _working = false;

  String get _path => '$_groups/${widget.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = AuthScope.of(context).token;
    if (_result == null || token != _loadedToken) {
      _loadedToken = token;
      _result = _load();
    }
  }

  Future<dynamic> _load() =>
      ActivitySeriesService.request(_path, token: _loadedToken);
  void _reload() => setState(() => _result = _load());

  Future<void> _change(
    String suffix, {
    String method = 'POST',
    SeriesRow? data,
  }) async {
    if (_working) return;
    final token = AuthScope.of(context).token;
    if (token == null || _working) return;
    setState(() => _working = true);
    try {
      await ActivitySeriesService.request(
        '$_path$suffix',
        method: method,
        token: token,
        data: data,
      );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) _groupError(context, error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('communityGroups'))),
    body: FutureBuilder<dynamic>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _GroupLoadError(snapshot.error, _reload);
        final data = snapshot.data as SeriesRow;
        final item = data['item'] as SeriesRow;
        final owner = AuthScope.of(context).user?.id == item['owner_id'];
        final joined = item['joined'] == true;
        final pending = item['pending'] == true;
        final approval = item['join_mode'] == 'approval';
        final events = ActivitySeriesService.rows(data['events']);
        final members = ActivitySeriesService.rows(data['members']);
        final applications = ActivitySeriesService.rows(data['applications']);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: _GroupSummary(item: item, detail: true),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!owner)
                  FilledButton(
                    onPressed: _working
                        ? null
                        : () => _change(
                            '/membership',
                            method: joined || pending ? 'DELETE' : 'PUT',
                          ),
                    child: Text(
                      context.tr(
                        joined
                            ? 'groupLeave'
                            : pending
                            ? 'groupCancelRequest'
                            : approval
                            ? 'groupApply'
                            : 'groupJoin',
                      ),
                    ),
                  ),
                if (item['conversation_id'] is String)
                  OutlinedButton.icon(
                    onPressed: () => widget.actions.openChat(context, item),
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(context.tr('communityGroupChat')),
                  ),
                OutlinedButton(
                  onPressed: () => widget.actions.openPerson(
                    context,
                    item['owner_id'] as String,
                  ),
                  child: Text(context.tr('groupOwner')),
                ),
              ],
            ),
            if (pending) _EmptyGroupText('groupPending'),
            if (!owner && !joined && !pending)
              _EmptyGroupText('groupMemberListNotice'),
            if (owner) ...[
              _heading(context, 'groupManage'),
              if (approval) ...[
                _heading(context, 'groupApplications'),
                if (applications.isEmpty)
                  _EmptyGroupText('groupApplicationsEmpty'),
                for (final applicant in applications)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(applicant['nickname'] as String),
                    onTap: () => widget.actions.openPerson(
                      context,
                      applicant['id'] as String,
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: context.tr('groupApprove'),
                          icon: const Icon(Icons.check_circle_outline),
                          onPressed: _working
                              ? null
                              : () => _change(
                                  '/applications/${applicant['id']}',
                                  data: {'accept': true},
                                ),
                        ),
                        IconButton(
                          tooltip: context.tr('groupReject'),
                          icon: const Icon(Icons.cancel_outlined),
                          onPressed: _working
                              ? null
                              : () => _change(
                                  '/applications/${applicant['id']}',
                                  data: {'accept': false},
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
              OutlinedButton.icon(
                onPressed: _working ? null : _announce,
                icon: const Icon(Icons.push_pin_outlined),
                label: Text(context.tr('groupPostAnnouncement')),
              ),
              OutlinedButton(
                onPressed: _working ? null : _attachActivity,
                child: Text(context.tr('groupAttachActivity')),
              ),
            ],
            _heading(context, 'groupEvents'),
            if (events.isEmpty) _EmptyGroupText('groupEventsEmpty'),
            for (final event in events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(event['title'] as String),
                onTap: () =>
                    widget.actions.openActivity(context, event['id'] as String),
              ),
            _heading(context, 'groupMembers'),
            for (final member in members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: RankedMemberName(
                  member['nickname'] as String,
                  level: member['member_level'],
                ),
                subtitle: MemberLevelBadge(member['member_level']),
                onTap: () =>
                    widget.actions.openPerson(context, member['id'] as String),
                trailing: owner && member['id'] != item['owner_id']
                    ? IconButton(
                        tooltip: context.tr('groupRemoveMember'),
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: _working ? null : () => _remove(member),
                      )
                    : null,
              ),
          ],
        );
      },
    ),
  );

  Future<void> _attachActivity() async {
    try {
      final data =
          await ActivitySeriesService.request(
                '/me/activities?owned=true&limit=100',
                token: _loadedToken,
              )
              as SeriesRow;
      if (!mounted) return;
      final events = ActivitySeriesService.rows(data['items'])
          .where(
            (item) =>
                item['visibility'] == 'public' &&
                item['event_status'] != 'cancelled',
          )
          .toList();
      final id = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: events.isEmpty
              ? _EmptyGroupText('groupEventsEmpty')
              : ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(events[index]['title'] as String),
                    onTap: () =>
                        Navigator.pop(context, events[index]['id'] as String),
                  ),
                ),
        ),
      );
      if (id != null && mounted)
        await _change('/events', method: 'PUT', data: {'eventId': id});
    } catch (error) {
      if (mounted) _groupError(context, error);
    }
  }

  Future<void> _remove(SeriesRow member) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('groupRemoveMember')),
        content: Text(member['nickname'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('groupRemoveMember')),
          ),
        ],
      ),
    );
    if (accepted == true && mounted)
      await _change('/members/${member['id']}', method: 'DELETE');
  }

  Future<void> _announce() async {
    String value = '';
    final body = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('groupPostAnnouncement')),
        content: TextField(
          maxLength: 500,
          maxLines: 4,
          onChanged: (text) => value = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
            },
            child: Text(context.tr('groupPublish')),
          ),
        ],
      ),
    );
    if (body != null && mounted)
      await _change('/announcements', data: {'body': body});
  }
}

Widget _heading(BuildContext context, String key) => Padding(
  padding: const EdgeInsets.only(top: 18, bottom: 6),
  child: Text(context.tr(key), style: Theme.of(context).textTheme.titleMedium),
);

class _GroupSummary extends StatelessWidget {
  const _GroupSummary({required this.item, required this.detail});
  final SeriesRow item;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final joined = context
        .tr('groupCount')
        .replaceAll('{count}', '${item['member_count']}');
    final capacity = item['capacity'];
    final ages = [item['min_age'], item['max_age']];
    final ageText = ages[0] != null && ages[1] != null
        ? '${ages[0]}–${ages[1]}'
        : ages[0] != null
        ? '${ages[0]}+'
        : ages[1] != null
        ? '≤${ages[1]}'
        : '';
    final categories =
        (item['categories'] as List?)?.whereType<String>() ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupCover(
          kind: item['cover_category_code'] as String?,
          url: (item['cover_url'] ?? item['category_cover_url']) as String?,
        ),
        Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                item['description'] as String,
                maxLines: detail ? null : 2,
                overflow: detail ? null : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 9),
              Text(
                [
                  if (item['region_name'] is String)
                    item['region_name'] as String,
                  capacity == null
                      ? joined
                      : '${item['member_count']} / $capacity',
                  context.tr(
                    item['join_mode'] == 'approval'
                        ? 'groupApproval'
                        : 'groupOpen',
                  ),
                  if (ageText.isNotEmpty)
                    context.tr('groupAgeRange').replaceAll('{ages}', ageText),
                ].join(' · '),
              ),
              if (categories.isNotEmpty)
                Wrap(
                  spacing: 5,
                  children: categories
                      .map(
                        (category) => Chip(
                          label: Text(category),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupCover extends StatelessWidget {
  const _GroupCover({this.kind, this.url, this.bytes});

  final String? kind;
  final String? url;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Image.asset(
      'assets/activity-covers/${kind ?? 'other'}.webp',
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xffe9edff),
        child: Center(child: Icon(Icons.groups_outlined, size: 44)),
      ),
    );
    return AspectRatio(
      aspectRatio: 16 / 8,
      child: switch ((bytes, url)) {
        (final Uint8List image, _) => Image.memory(
          image,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
        (_, final String photo) => Image.network(
          Uri.parse(_api).resolve(photo).toString(),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => fallback(),
        ),
        _ => fallback(),
      },
    );
  }
}

class _GroupEditor extends StatefulWidget {
  const _GroupEditor({required this.token});
  final String token;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _capacity = TextEditingController(text: '50');
  final _min = TextEditingController();
  final _max = TextEditingController();
  final Set<String> _selected = {};
  late Future<List<dynamic>> _catalogs = _load();
  String? _region;
  String? _coverType;
  String? _created;
  bool _approval = false;
  bool _saving = false;
  Uint8List? _image;

  Future<List<dynamic>> _load() => Future.wait([
    ActivitySeriesService.request('/categories'),
    ActivitySeriesService.request('/regions'),
  ]);

  @override
  void dispose() {
    for (final input in [_title, _description, _capacity, _min, _max]) {
      input.dispose();
    }
    super.dispose();
  }

  String _name(BuildContext context, SeriesRow item) =>
      (item[switch (Localizations.localeOf(context).languageCode) {
                'ko' => 'name_ko_kr',
                'en' => 'name_en_us',
                _ => 'name_zh_cn',
              }] ??
              item['name_zh_cn'])
          .toString();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('groupCreate'))),
    body: FutureBuilder<List<dynamic>>(
      future: _catalogs,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return _GroupLoadError(
            snapshot.error,
            () => setState(() => _catalogs = _load()),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final categories = ActivitySeriesService.rows(
          snapshot.data![0],
        ).where((item) => item['level'] == 1);
        final coverCategory = categories
            .where((item) => item['id'] == _coverType)
            .firstOrNull;
        final regions = ActivitySeriesService.rows(
          snapshot.data![1],
        ).where((item) => item['level'] == 1);
        return Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _field(_title, 'groupTitle', maxLength: 100, required: true),
              _field(
                _description,
                'groupDescription',
                maxLength: 1000,
                required: true,
                lines: 4,
              ),
              DropdownButtonFormField<String>(
                initialValue: _region ?? '',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.tr('groupRegion'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.tr('groupAnyRegion')),
                  ),
                  for (final region in regions)
                    DropdownMenuItem(
                      value: region['code'] as String,
                      child: Text(_name(context, region)),
                    ),
                ],
                onChanged: (code) => _region = code == '' ? null : code,
              ),
              _heading(context, 'groupCategories'),
              Wrap(
                spacing: 8,
                children: [
                  for (final category in categories)
                    FilterChip(
                      label: Text(_name(context, category)),
                      selected: _selected.contains(category['id']),
                      onSelected: (selected) => setState(() {
                        final id = category['id'] as String;
                        if (selected) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                          if (_coverType == id) _coverType = null;
                        }
                      }),
                    ),
                ],
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(_coverType),
                initialValue: _coverType ?? '',
                decoration: InputDecoration(
                  labelText: context.tr('groupSystemCover'),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.tr('groupDefaultCover')),
                  ),
                  for (final category in categories.where(
                    (item) => _selected.contains(item['id']),
                  ))
                    DropdownMenuItem(
                      value: category['id'] as String,
                      child: Text(_name(context, category)),
                    ),
                ],
                onChanged: (id) =>
                    setState(() => _coverType = id == '' ? null : id),
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      image: true,
                      label: context.tr('groupCoverPreview'),
                      child: _GroupCover(
                        bytes: _image,
                        kind: coverCategory?['code'] as String?,
                        url: coverCategory?['cover_image_url'] as String?,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _pickCover,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              context.tr(
                                _image == null
                                    ? 'groupUploadCover'
                                    : 'groupReplaceCover',
                              ),
                            ),
                          ),
                          if (_image != null)
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _image = null),
                              child: Text(context.tr('groupClearCover')),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _field(
                _capacity,
                'groupCapacity',
                min: 2,
                max: 50,
                required: true,
              ),
              _field(_min, 'groupMinAge', min: 14, max: 120),
              _field(_max, 'groupMaxAge', min: 14, max: 120),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  context.tr(_approval ? 'groupApproval' : 'groupOpen'),
                ),
                value: _approval,
                onChanged: (approval) => setState(() => _approval = approval),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  context.tr(
                    _created == null ? 'groupPublish' : 'groupRetryCover',
                  ),
                ),
              ),
              if (_created case final String id)
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context, id),
                  child: Text(context.tr('groupViewCreated')),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _field(
    TextEditingController input,
    String label, {
    int? min,
    int? max,
    int? maxLength,
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextFormField(
      controller: input,
      maxLines: lines,
      maxLength: maxLength,
      keyboardType: min == null ? null : TextInputType.number,
      decoration: InputDecoration(labelText: context.tr(label)),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && (text.isEmpty || (min == null && text.length < 2))) {
          return context.tr('groupInvalidField');
        }
        if (min != null && text.isNotEmpty) {
          final number = int.tryParse(text);
          if (number == null || number < min || number > max!)
            return context.tr('groupInvalidField');
        }
        return null;
      },
    ),
  );

  Future<void> _pickCover() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (photo == null) return;
      final bytes = await compute(prepareEventCover, await photo.readAsBytes());
      if (mounted) setState(() => _image = bytes);
    } catch (error) {
      if (mounted) _groupError(context, error);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final min = int.tryParse(_min.text.trim());
    final max = int.tryParse(_max.text.trim());
    if (min != null && max != null && max < min) {
      _groupError(context, context.tr('groupInvalidField'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_created == null) {
        final created =
            await ActivitySeriesService.request(
                  _groups,
                  token: widget.token,
                  method: 'POST',
                  data: {
                    'title': _title.text.trim(),
                    'description': _description.text.trim(),
                    'regionCode': _region,
                    'categoryIds': _selected.toList(),
                    'coverCategoryId': _coverType,
                    'capacity': int.tryParse(_capacity.text.trim()),
                    'minAge': min,
                    'maxAge': max,
                    'joinMode': _approval ? 'approval' : 'open',
                  },
                )
                as SeriesRow;
        _created = created['id'] as String;
      }
      if (_image case final Uint8List image) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_api$_groups/$_created/cover'),
        );
        request.headers['Authorization'] = 'Bearer ${widget.token}';
        request.files.add(
          http.MultipartFile.fromBytes(
            'cover',
            image,
            filename: 'cover.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );
        final response = await http.Response.fromStream(
          await SessionTransport.client.send(request),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final payload = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
          throw StateError(
            payload['error']?['message'] as String? ?? 'groupCoverFailed',
          );
        }
      }
      if (mounted) Navigator.pop(context, _created);
    } catch (error) {
      if (mounted) _groupError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _EmptyGroupText extends StatelessWidget {
  const _EmptyGroupText(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(context.tr(label)),
  );
}

class _GroupLoadError extends StatelessWidget {
  const _GroupLoadError(this.error, this.retry);
  final Object? error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$error', textAlign: TextAlign.center),
          TextButton(onPressed: retry, child: Text(context.tr('reload'))),
        ],
      ),
    ),
  );
}

void _groupError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is FormatException ? context.tr(error.message) : '$error',
        ),
      ),
    );
