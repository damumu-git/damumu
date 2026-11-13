import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'activity_text.dart';
import 'auth.dart';
import 'event_service.dart';
import 'l10n.dart';
import 'social_service.dart';
import 'user_avatar_image.dart';

class ActivityBookmarkButton extends StatefulWidget {
  const ActivityBookmarkButton({
    required this.token,
    required this.id,
    super.key,
  });

  final String token;
  final String id;

  @override
  State<ActivityBookmarkButton> createState() => _ActivityBookmarkButtonState();
}

class _ActivityBookmarkButtonState extends State<ActivityBookmarkButton> {
  bool? _saved;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update({bool toggle = false}) async {
    setState(() => _busy = true);
    try {
      final saved = _saved;
      if (toggle && saved != null) {
        await SocialService.setSaved(
          widget.token,
          'activity',
          widget.id,
          !saved,
        );
        if (mounted) setState(() => _saved = !saved);
      } else {
        final current = await SocialService.isSaved(
          widget.token,
          'activity',
          widget.id,
        );
        if (mounted) setState(() => _saved = current);
      }
    } catch (error) {
      if (mounted && toggle) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: context.tr(_saved == true ? 'memberUnsave' : 'memberSave'),
    icon: Icon(_saved == true ? Icons.bookmark : Icons.bookmark_outline),
    onPressed: _busy ? null : () => _update(toggle: true),
  );
}

class MemberPublicDetails extends StatelessWidget {
  const MemberPublicDetails({required this.profile, super.key});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final suffix = switch (Localizations.localeOf(context).languageCode) {
      'ko' => '_ko_kr',
      'en' => '_en_us',
      _ => '',
    };
    String? name(String field) =>
        profile[field + suffix] as String? ?? profile[field] as String?;
    final region = name('home_region_name');
    final bio = profile['bio'] as String?;
    if (region == null && (bio == null || bio.isEmpty)) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (region != null)
                Chip(
                  avatar: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(
                    [name('home_parent_name'), region].nonNulls.join(' · '),
                  ),
                ),
              if (bio != null && bio.isNotEmpty) Text(bio),
            ],
          ),
        ),
      ),
    );
  }
}

class MemberProfileEditor extends StatefulWidget {
  const MemberProfileEditor({required this.token, super.key});

  final String token;

  @override
  State<MemberProfileEditor> createState() => _MemberProfileEditorState();
}

class _MemberProfileEditorState extends State<MemberProfileEditor> {
  final _bio = TextEditingController();
  List<AdministrativeRegion> _regions = [];
  String? _city;
  String? _district;
  String? _savedRegion;
  bool _visible = false;
  bool _loading = true;
  bool _catalogFailed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final regions = RegionService.load().catchError(
      (Object _) => <AdministrativeRegion>[],
    );
    try {
      final profile = await SocialService.memberProfile(widget.token);
      final catalog = await regions;
      if (!mounted) return;
      _bio.text = profile['bio'] as String? ?? '';
      final code = profile['home_region_code'] as String?;
      final selected = catalog
          .where((region) => region.code == code)
          .firstOrNull;
      setState(() {
        _savedRegion = code;
        _regions = catalog;
        _catalogFailed = catalog.isEmpty;
        _city = selected?.parentCode ?? selected?.code;
        _district = selected?.level == 2 ? selected?.code : null;
        _visible = profile['show_home_region'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SocialService.saveMemberProfile(
        widget.token,
        _bio.text,
        _catalogFailed ? _savedRegion : _district ?? _city,
        _visible,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    Widget picker(
      String label,
      String? current,
      Iterable<AdministrativeRegion> options,
      ValueChanged<String?> onChanged, {
      bool enabled = true,
    }) => InputDecorator(
      decoration: InputDecoration(labelText: context.tr(label)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: current ?? '',
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(context.tr('memberOptional')),
            ),
            for (final option in options)
              DropdownMenuItem(
                value: option.code,
                child: Text(
                  option.displayName(language),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _saving || !enabled
              ? null
              : (value) => onChanged(value == '' ? null : value),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('memberEditProfile'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _load,
                    child: Text(context.tr('retry')),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _bio,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: context.tr('memberBio'),
                  ),
                ),
                const SizedBox(height: 12),
                if (_catalogFailed)
                  Text(context.tr('memberRegionUnavailable'))
                else ...[
                  picker(
                    'memberHomeCity',
                    _city,
                    _regions.where((r) => r.level == 1),
                    (value) => setState(() {
                      _city = value;
                      _district = null;
                      if (value == null) _visible = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  picker(
                    'memberHomeDistrict',
                    _district,
                    _regions.where(
                      (r) => r.level == 2 && r.parentCode == _city,
                    ),
                    (value) => setState(() => _district = value),
                    enabled: _city != null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('memberShowRegion')),
                    subtitle: Text(context.tr('memberRegionHelp')),
                    value: _visible,
                    onChanged: _city == null || _saving
                        ? null
                        : (value) => setState(() => _visible = value),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(context.tr('memberSaveProfile')),
                ),
              ],
            ),
    );
  }
}

class MemberLibraryPage extends StatefulWidget {
  const MemberLibraryPage({
    required this.token,
    required this.following,
    required this.openPerson,
    required this.openActivity,
    required this.activityThumbnail,
    super.key,
  });

  final String token;
  final bool following;
  final Future<void> Function(BuildContext, String) openPerson;
  final Future<void> Function(BuildContext, String) openActivity;
  final Widget Function(BuildContext, Map<String, dynamic>) activityThumbnail;

  @override
  State<MemberLibraryPage> createState() => _MemberLibraryPageState();
}

class _MemberLibraryPageState extends State<MemberLibraryPage> {
  final _items = <Map<String, dynamic>>[];
  final _removing = <String>{};
  bool _loading = false;
  bool _more = false;
  String? _error;
  String _kind = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (_loading || _removing.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = widget.following
          ? await SocialService.following(
              widget.token,
              append ? _items.length : 0,
            )
          : {
              'items': await SocialService.savedItems(widget.token),
              'hasMore': false,
            };
      if (!mounted) return;
      setState(() {
        if (!append) _items.clear();
        _items.addAll((page['items'] as List).cast<Map<String, dynamic>>());
        _more = page['hasMore'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> item, String id) async {
    setState(() => _removing.add(id));
    try {
      if (widget.following) {
        await SocialService.followContact(widget.token, id, false);
      } else {
        await SocialService.setSaved(
          widget.token,
          item['kind'] as String,
          id,
          false,
        );
      }
      if (mounted) setState(() => _items.remove(item));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _removing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _items
        .where((item) => _kind.isEmpty || item['kind'] == _kind)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(widget.following ? 'memberFollowing' : 'memberSaved'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.following)
              Wrap(
                spacing: 8,
                children: [
                  for (final (value, label) in [
                    ('', 'memberAll'),
                    ('activity', 'memberAllActivities'),
                    ('guide', 'memberGuides'),
                  ])
                    ChoiceChip(
                      label: Text(context.tr(label)),
                      selected: _kind == value,
                      onSelected: (_) => setState(() => _kind = value),
                    ),
                ],
              ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: _load, child: Text(context.tr('retry'))),
            ],
            if (rows.isEmpty && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr(
                    widget.following
                        ? 'memberFollowingEmpty'
                        : 'memberSavedEmpty',
                  ),
                ),
              ),
            for (final item in rows) _row(context, item),
            if (_more)
              TextButton(
                onPressed: _loading || _removing.isNotEmpty
                    ? null
                    : () => _load(append: true),
                child: Text(context.tr('loadMore')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> item) {
    final id = (widget.following ? item['id'] : item['target']) as String;
    final title =
        (widget.following ? item['nickname'] : item['title']) as String;
    final guide = item['kind'] == 'guide';
    final start = DateTime.tryParse('${item['starts_at']}');
    final subtitle = [
      if (widget.following && item['mutual'] == true)
        context.tr('memberMutual'),
      if (widget.following && item['bio'] is String) item['bio'] as String,
      if (guide) context.tr('memberGuides'),
      if (start != null) activityTime(context, start),
    ];
    return Card(
      child: ListTile(
        leading: widget.following
            ? UserAvatarImage(
                nickname: title,
                avatarUrl: item['avatar_url'] as String?,
                radius: 22,
              )
            : SizedBox.square(
                dimension: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: guide
                      ? const Icon(Icons.auto_stories_outlined)
                      : widget.activityThumbnail(context, item),
                ),
              ),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: !widget.following && !guide
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ActivityListTags(
                    data: item,
                    category: item['category_name'] as String? ?? '',
                    owned:
                        AuthScope.of(context).user?.id ==
                            item['organizer_user_id'] &&
                        item['organizer_user_id'] != null,
                  ),
                  if (subtitle.isNotEmpty) Text(subtitle.join(' · ')),
                ],
              )
            : subtitle.isEmpty
            ? null
            : Text(
                subtitle.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: IconButton(
          tooltip: context.tr(
            widget.following ? 'contactUnfollow' : 'memberUnsave',
          ),
          icon: Icon(
            widget.following
                ? Icons.person_remove_outlined
                : Icons.bookmark_remove_outlined,
          ),
          onPressed: _loading || _removing.contains(id)
              ? null
              : () => _remove(item, id),
        ),
        onTap: () async {
          if (widget.following) {
            await widget.openPerson(context, id);
          } else if (guide) {
            await launchUrl(
              Uri.https('app.damumu.com', '/guides/$id'),
              mode: LaunchMode.externalApplication,
            );
          } else {
            await widget.openActivity(context, id);
          }
          if (mounted && !guide) await _load();
        },
      ),
    );
  }
}
