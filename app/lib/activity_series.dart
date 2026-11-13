import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'activity_text.dart';
import 'auth.dart';
import 'event_service.dart';
import 'event_cover_image.dart';
import 'l10n.dart';

const _api = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.damumu.com/api/v1',
);
typedef SeriesRow = Map<String, dynamic>;
typedef OpenSeriesEvent = void Function(BuildContext context, String id);

class ActivitySeriesService {
  static Future<dynamic> request(
    String path, {
    String? token,
    String method = 'GET',
    SeriesRow? data,
  }) async {
    final request = http.Request(method, Uri.parse('$_api$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (data != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(data);
    }
    final response = await http.Response.fromStream(
      await request.send(),
    ).timeout(const Duration(seconds: 12));
    final envelope = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EventServiceException(
        envelope['error']?['message'] as String? ?? 'Request failed',
      );
    }
    return envelope['data'];
  }

  static List<SeriesRow> rows(dynamic value) =>
      (value as List).cast<SeriesRow>();
}

String _seriesKey(SeriesRow item) => (item['slug'] ?? item['id']) as String;
Widget? _eventTime(BuildContext context, SeriesRow item) {
  final date = DateTime.tryParse('${item['starts_at']}');
  return date == null ? null : Text(activityTime(context, date));
}

class ActivitySeriesPage extends StatefulWidget {
  const ActivitySeriesPage({
    required this.openEvent,
    this.ownerId,
    this.seriesKey,
    super.key,
  });
  final String? ownerId;
  final String? seriesKey;
  final OpenSeriesEvent openEvent;

  @override
  State<ActivitySeriesPage> createState() => _ActivitySeriesPageState();
}

class _ActivitySeriesPageState extends State<ActivitySeriesPage> {
  late Future<dynamic> _result;
  List<SeriesRow> _regions = [];
  String? _region;
  String? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = AuthScope.of(context).token;
    if (_token == token && _started) return;
    _token = token;
    _started = true;
    _result = _load();
  }

  bool _started = false;

  Future<dynamic> _load() async {
    final key = widget.seriesKey;
    if (key != null) {
      return ActivitySeriesService.request(
        '/series/${Uri.encodeComponent(key)}',
        token: _token,
      );
    }
    final query = Uri(
      queryParameters: {
        'region': ?_region,
        if (widget.ownerId != null) 'ownerId': widget.ownerId!,
      },
    ).query;
    final results = await Future.wait([
      ActivitySeriesService.request('/series${query.isEmpty ? '' : '?$query'}'),
      ActivitySeriesService.request('/regions'),
    ]);
    _regions = ActivitySeriesService.rows(results[1]);
    return results[0];
  }

  void _refresh() => setState(() => _result = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('seriesTitle'))),
    body: FutureBuilder(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: Text(context.tr('reload')),
            ),
          );
        }
        if (widget.seriesKey == null) {
          return _index(ActivitySeriesService.rows(snapshot.data));
        }
        final result = snapshot.data as SeriesRow;
        final item = result['item'] as SeriesRow;
        return _SeriesDetail(
          key: ValueKey(item['id']),
          item: item,
          events: ActivitySeriesService.rows(result['events']),
          token: _token,
          openEvent: widget.openEvent,
          refresh: _refresh,
        );
      },
    ),
  );

  Widget _index(List<SeriesRow> rows) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (widget.ownerId == null) ...[
        if (_region != null)
          TextButton(
            onPressed: () =>
                launchUrl(Uri.https('app.damumu.com', '/places/$_region')),
            child: Text(context.tr('seriesRegionGuide')),
          ),
        DropdownButtonFormField<String>(
          initialValue: _region ?? '',
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('seriesRegion')),
          items: _regionItems(context, _regions, includeAll: true),
          onChanged: (value) {
            _region = value == '' ? null : value;
            _refresh();
          },
        ),
        if (_token != null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _create(false),
                child: Text(context.tr('seriesCreate')),
              ),
              TextButton(
                onPressed: () => _create(true),
                child: Text(context.tr('seriesPartner')),
              ),
            ],
          ),
      ],
      if (rows.isEmpty) Text(context.tr('seriesEmpty')),
      for (final item in rows)
        Card(
          child: ListTile(
            title: Text(item['title'] as String),
            subtitle: Text(
              [
                item['region_name'],
                item['description'],
              ].whereType<String>().join('\n'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ActivitySeriesPage(
                  seriesKey: _seriesKey(item),
                  openEvent: widget.openEvent,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> _create(bool proposal) async {
    final result = await Navigator.of(context).push<SeriesRow>(
      MaterialPageRoute(
        builder: (_) => _SeriesEditor(
          token: _token!,
          regions: _regions,
          proposal: proposal,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (proposal) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('seriesSaved'))));
    } else {
      _refresh();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActivitySeriesPage(
            seriesKey: _seriesKey(result),
            openEvent: widget.openEvent,
          ),
        ),
      );
    }
  }
}

List<DropdownMenuItem<String>> _regionItems(
  BuildContext context,
  List<SeriesRow> rows, {
  bool includeAll = false,
}) {
  final language = Localizations.localeOf(context).languageCode;
  final field = switch (language) {
    'ko' => 'name_ko_kr',
    'en' => 'name_en_us',
    _ => 'name_zh_cn',
  };
  final labels = {
    for (final row in rows)
      row['code']: (row[field] ?? row['name_zh_cn']) as String,
  };
  return [
    if (includeAll)
      DropdownMenuItem(value: '', child: Text(context.tr('seriesAllRegions'))),
    for (final item in rows)
      DropdownMenuItem(
        value: item['code'] as String,
        child: Text(
          [
            labels[item['parent_code']],
            labels[item['code']],
          ].whereType<String>().join(' / '),
          overflow: TextOverflow.ellipsis,
        ),
      ),
  ];
}

class _SeriesEditor extends StatefulWidget {
  const _SeriesEditor({
    required this.token,
    required this.regions,
    required this.proposal,
  });
  final String token;
  final List<SeriesRow> regions;
  final bool proposal;

  @override
  State<_SeriesEditor> createState() => _SeriesEditorState();
}

class _SeriesEditorState extends State<_SeriesEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _region;
  String _kind = 'organizer';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item =
          await ActivitySeriesService.request(
                widget.proposal ? '/series/proposals' : '/series',
                token: widget.token,
                method: 'POST',
                data: {
                  'regionCode': _region,
                  if (widget.proposal) ...{
                    'kind': _kind,
                    'body': _body.text,
                  } else ...{
                    'title': _title.text,
                    'description': _body.text,
                  },
                },
              )
              as SeriesRow;
      if (mounted) Navigator.of(context).pop(item);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        context.tr(widget.proposal ? 'seriesPartner' : 'seriesCreate'),
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.proposal)
            DropdownButtonFormField<String>(
              initialValue: _kind,
              items: [
                DropdownMenuItem(
                  value: 'organizer',
                  child: Text(context.tr('seriesHost')),
                ),
                DropdownMenuItem(
                  value: 'venue',
                  child: Text(context.tr('seriesVenue')),
                ),
              ],
              onChanged: _busy ? null : (value) => _kind = value!,
            )
          else
            TextFormField(
              controller: _title,
              maxLength: 100,
              decoration: InputDecoration(labelText: context.tr('seriesName')),
              validator: (value) => value!.trim().length < 2
                  ? context.tr('seriesRequired')
                  : null,
            ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('seriesRegion')),
            items: _regionItems(context, widget.regions),
            onChanged: _busy ? null : (value) => _region = value,
            validator: (value) =>
                value == null ? context.tr('seriesRequired') : null,
          ),
          TextFormField(
            controller: _body,
            maxLength: 1000,
            minLines: 3,
            maxLines: 7,
            decoration: InputDecoration(
              labelText: context.tr('seriesDescription'),
            ),
            validator: (value) =>
                value!.trim().length < 2 ? context.tr('seriesRequired') : null,
          ),
          if (_error != null) Text(_error!),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(context.tr('save')),
          ),
        ],
      ),
    ),
  );
}

class _SeriesDetail extends StatefulWidget {
  const _SeriesDetail({
    required this.item,
    required this.events,
    required this.token,
    required this.openEvent,
    required this.refresh,
    super.key,
  });
  final SeriesRow item;
  final List<SeriesRow> events;
  final String? token;
  final OpenSeriesEvent openEvent;
  final VoidCallback refresh;

  @override
  State<_SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<_SeriesDetail> {
  late bool _subscribed = widget.item['subscribed'] == true;
  late String _slot = widget.item['interest_slot'] as String? ?? '';
  bool _busy = false;
  String? _error;

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) widget.refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _addEvent() async {
    final token = widget.token!;
    final mine = await EventService.myActivities(token);
    if (!mounted) return;
    final owner = AuthScope.of(context).user?.id;
    final linked = widget.events.map((item) => item['id']).toSet();
    final events = mine.where(
      (row) =>
          row['organizer_user_id'] == owner &&
          ['published', 'full', 'completed'].contains(row['event_status']) &&
          !linked.contains(row['id']),
    );
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.tr('seriesAddEvent')),
        children: [
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.tr('seriesEmpty')),
            ),
          for (final event in events)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, event['id'] as String),
              child: Text(event['title'] as String),
            ),
        ],
      ),
    );
    if (!mounted || id == null) return;
    await ActivitySeriesService.request(
      '/series/${widget.item['id']}/events/$id',
      token: token,
      method: 'PUT',
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        widget.item['title'] as String,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      if (widget.item['region_name'] != null)
        Text(widget.item['region_name'] as String),
      Text(widget.item['description'] as String),
      if (widget.item['guide_slug'] is String)
        TextButton(
          onPressed: () => launchUrl(
            Uri.https('app.damumu.com', '/guides/${widget.item['guide_slug']}'),
          ),
          child: Text(widget.item['guide_title'] as String),
        ),
      if (widget.item['can_manage'] == true)
        TextButton(
          onPressed: _busy ? null : () => _act(_addEvent),
          child: Text(context.tr('seriesAddEvent')),
        ),
      if (widget.token != null) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _subscribed,
          title: Text(context.tr('seriesSubscribe')),
          onChanged: _busy
              ? null
              : (value) => setState(() => _subscribed = value),
        ),
        DropdownButtonFormField<String>(
          initialValue: _slot,
          decoration: InputDecoration(labelText: context.tr('seriesInterest')),
          items: [
            for (final entry in const {
              '': 'seriesNoSlot',
              'saturday': 'seriesSat',
              'sunday': 'seriesSun',
              'either': 'seriesEither',
            }.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(context.tr(entry.value)),
              ),
          ],
          onChanged: _busy ? null : (value) => _slot = value!,
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _act(() async {
                  await ActivitySeriesService.request(
                    '/series/${widget.item['id']}/membership',
                    method: 'PUT',
                    token: widget.token,
                    data: {
                      'subscribed': _subscribed,
                      'interestSlot': _slot.isEmpty ? null : _slot,
                    },
                  );
                }),
          child: Text(context.tr('save')),
        ),
      ],
      if (_error != null) Text(_error!),
      Text(
        context
            .tr('seriesInterestCount')
            .replaceFirst('{count}', '${widget.item['interest_count']}'),
      ),
      for (final ended in [false, true]) ...[
        const SizedBox(height: 16),
        Text(
          context.tr(ended ? 'seriesPast' : 'seriesNext'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (!widget.events.any((item) => item['ended'] == ended))
          Text(context.tr(ended ? 'seriesEmpty' : 'seriesNoNext')),
        for (final event in widget.events.where(
          (item) => item['ended'] == ended,
        ))
          ListTile(
            title: Text(event['title'] as String),
            subtitle: _eventTime(context, event),
            trailing: event['has_recap'] == true
                ? IconButton(
                    tooltip: context.tr('seriesRecap'),
                    icon: const Icon(Icons.article_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityRecapPage(
                          id: event['id'] as String,
                          openEvent: widget.openEvent,
                        ),
                      ),
                    ),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => widget.openEvent(context, event['id'] as String),
          ),
      ],
    ],
  );
}

class ActivityRecapPage extends StatefulWidget {
  const ActivityRecapPage({
    required this.id,
    required this.openEvent,
    super.key,
  });
  final String id;
  final OpenSeriesEvent openEvent;

  @override
  State<ActivityRecapPage> createState() => _ActivityRecapPageState();
}

class _ActivityRecapPageState extends State<ActivityRecapPage> {
  late Future<dynamic> _story = ActivitySeriesService.request(
    '/events/${widget.id}/story',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('seriesRecap'))),
    body: FutureBuilder(
      future: _story,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () {
                setState(
                  () => _story = ActivitySeriesService.request(
                    '/events/${widget.id}/story',
                  ),
                );
              },
              child: Text(context.tr('reload')),
            ),
          );
        }
        final item = snapshot.data as SeriesRow;
        final auth = AuthScope.of(context);
        final image = item['cover_url'] as String?;
        final photos = ActivitySeriesService.rows(item['recap_photos'] ?? []);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              item['title'] as String,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (item['recap_show_cover'] == true && image != null)
              Image.network(
                absoluteImageUrl(image),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Text(item['recap'] as String? ?? context.tr('seriesNoRecap')),
            for (final photo in photos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Image.network(
                  absoluteImageUrl(photo['image_url'] as String),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (item['ended'] == true &&
                auth.user?.id == item['organizer_user_id'] &&
                auth.token != null)
              TextButton(
                onPressed: () => _edit(item, auth.token!),
                child: Text(context.tr('seriesEditRecap')),
              ),
            if (item['series_id'] != null)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ActivitySeriesPage(
                      seriesKey:
                          (item['series_slug'] ?? item['series_id']) as String,
                      openEvent: widget.openEvent,
                    ),
                  ),
                ),
                child: Text(item['series_title'] as String),
              ),
            if (item['next_event_id'] is String)
              FilledButton(
                onPressed: () =>
                    widget.openEvent(context, item['next_event_id'] as String),
                child: Text(context.tr('seriesNext')),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _edit(SeriesRow item, String token) async {
    var body = item['recap'] as String? ?? '';
    var cover = item['recap_show_cover'] == true;
    var files = <XFile>[];
    var clearPhotos = false;
    var photosApproved = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.tr('seriesEditRecap')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: body,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                  onChanged: (value) => update(() => body = value),
                ),
                CheckboxListTile(
                  value: cover,
                  title: Text(context.tr('seriesRecapCover')),
                  onChanged: (value) => update(() => cover = value ?? false),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(context.tr('seriesPhotos')),
                  onPressed: () async {
                    try {
                      final picked = await ImagePicker().pickMultiImage(
                        limit: 3,
                      );
                      if (context.mounted && picked.isNotEmpty) {
                        update(() => files = picked.take(3).toList());
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$error')));
                      }
                    }
                  },
                ),
                for (final photo in files)
                  Text(
                    photo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                CheckboxListTile(
                  value: clearPhotos,
                  title: Text(context.tr('seriesRemovePhotos')),
                  onChanged: (value) =>
                      update(() => clearPhotos = value ?? false),
                ),
                if (files.isNotEmpty)
                  CheckboxListTile(
                    value: photosApproved,
                    title: Text(context.tr('seriesPhotoConsent')),
                    onChanged: (value) =>
                        update(() => photosApproved = value ?? false),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed:
                  body.trim().length < 2 ||
                      (files.isNotEmpty && !photosApproved)
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(context.tr('save')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || save != true) return;
    final uploaded = <String>[];
    try {
      for (final file in files) {
        final image = await EventService.uploadCover(
          token,
          prepareEventCover(await file.readAsBytes()),
        );
        uploaded.add(image.id);
      }
      final photoIds = files.isNotEmpty || clearPhotos
          ? uploaded
          : ActivitySeriesService.rows(
              item['recap_photos'] ?? [],
            ).map((photo) => photo['id'] as String).toList();
      await ActivitySeriesService.request(
        '/events/${widget.id}/recap',
        token: token,
        method: 'PUT',
        data: {
          'body': body,
          'showCover': cover,
          'photoIds': photoIds,
          'photosApproved': photosApproved || files.isEmpty,
        },
      );
      if (mounted) {
        setState(
          () => _story = ActivitySeriesService.request(
            '/events/${widget.id}/story',
          ),
        );
      }
    } catch (error) {
      for (final id in uploaded) {
        try {
          await EventService.deleteCover(token, id);
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

Future<void> copyActivityShare(BuildContext context, String id) async {
  final url = 'https://app.damumu.com/activities/$id/share';
  try {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('seriesShareCopied'))));
    }
  } on PlatformException {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('seriesShare')),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel')),
          ),
        ],
      ),
    );
  }
}
