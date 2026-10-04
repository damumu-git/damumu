import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth.dart';
import 'activity_interactions.dart';
import 'category_service.dart';
import 'chat_image.dart';
import 'event_service.dart';
import 'feedback.dart';
import 'feedback_model.dart';
import 'l10n.dart';
import 'build_failure.dart';
import 'location_service.dart';
import 'event_cover_image.dart';
import 'social_service.dart';
import 'web_cropper_layout.dart';
import 'realtime_service.dart';
import 'push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.initializeFirebase();
  runApp(const DaziApp());
}

const _ink = Color(0xFF17162C);
const _green = Color(0xFF5B4BDB);
const _mint = Color(0xFFEDEAFF);
const _cream = Color(0xFFF3F5FA);
const _orange = Color(0xFFFF6B57);

_AppShellState? _activeShell;
_CreateEventPageState? _activeRouteDraft;

Future<void> _goHome(BuildContext context) async {
  final draft = _activeRouteDraft;
  if (draft != null && !await draft._confirmLeave()) return;
  if (!context.mounted) return;
  if (await _activeShell?._selectHome() == false) return;
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class _HomeAction extends StatelessWidget {
  const _HomeAction();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.tr('returnHome'),
    onPressed: () => _goHome(context),
    icon: const Icon(Icons.home_outlined),
  );
}

class DaziApp extends StatefulWidget {
  const DaziApp({super.key, this.home, this.authController});
  final Widget? home;
  final AuthController? authController;

  @override
  State<DaziApp> createState() => _DaziAppState();
}

class _DaziAppState extends State<DaziApp> {
  Locale _locale = const Locale('zh');
  late final AuthController _authController;
  late final bool _ownsAuthController;
  Key? _recoveryKey;
  ErrorWidgetBuilder? _previousErrorBuilder;
  ErrorWidgetBuilder? _installedErrorBuilder;
  static const _isTestEnvironment = bool.fromEnvironment('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _authController = widget.authController ?? AuthController();
    _ownsAuthController = widget.authController == null;
    if (widget.home == null) _authController.restore();
    if (!_isTestEnvironment) _previousErrorBuilder = ErrorWidget.builder;
    AppLocaleScope.restore().then((value) {
      if (mounted) setState(() => _locale = value);
    });
  }

  @override
  void dispose() {
    if (identical(ErrorWidget.builder, _installedErrorBuilder) &&
        _previousErrorBuilder != null) {
      ErrorWidget.builder = _previousErrorBuilder!;
    }
    if (_ownsAuthController) _authController.dispose();
    super.dispose();
  }

  Future<void> _setLocale(Locale locale) async {
    setState(() => _locale = locale);
    await (await SharedPreferences.getInstance()).setString(
      'app_locale',
      locale.languageCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLocaleScope(
      locale: _locale,
      onChanged: _setLocale,
      child: AuthScope(
        controller: _authController,
        child: MaterialApp(
          key: _recoveryKey,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            // Flutter still reports the full exception to developer diagnostics.
            // Only the widget presented to the user is replaced.
            if (!_isTestEnvironment) {
              _previousErrorBuilder ??= ErrorWidget.builder;
              _installedErrorBuilder = (_) => BuildFailure(
                title: context.tr('buildErrorTitle'),
                message: context.tr('buildErrorMessage'),
                retryLabel: context.tr('retry'),
                onRetry: () {
                  if (mounted) setState(() => _recoveryKey = UniqueKey());
                },
              );
              ErrorWidget.builder = _installedErrorBuilder!;
            }
            return child!;
          },
          title: '搭慕慕',
          locale: _locale,
          supportedLocales: const [Locale('zh'), Locale('en'), Locale('ko')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _green,
              primary: _green,
              surface: _cream,
            ),
            scaffoldBackgroundColor: _cream,
            fontFamily: 'Noto Sans SC',
            fontFamilyFallback: const [
              'Noto Sans KR',
              'Segoe UI Emoji',
              'Apple Color Emoji',
              'Noto Color Emoji',
              'Noto Emoji',
              'PingFang SC',
              'Microsoft YaHei',
              'Noto Sans CJK SC',
            ],
            textTheme: const TextTheme(
              headlineLarge: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.12,
                color: _ink,
              ),
              headlineSmall: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
              titleLarge: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
              bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: _ink),
              bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: _ink),
            ),
            cardTheme: const CardThemeData(
              elevation: 0,
              color: Colors.white,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(22)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE7E5DF)),
              ),
            ),
          ),
          home: widget.home ?? _authenticatedHome(),
        ),
      ),
    );
  }

  Widget _authenticatedHome() => AnimatedBuilder(
    animation: _authController,
    builder: (context, _) {
      if (_authController.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return _authController.user == null ? const AuthPage() : const AppShell();
    },
  );
}

class EventItem {
  EventItem({
    required this.id,
    required this.emoji,
    required this.title,
    required this.category,
    required this.time,
    required this.area,
    required this.distance,
    required this.host,
    required this.hostScore,
    required this.joined,
    required this.capacity,
    this.apiId,
    this.organizerUserId,
    this.organizerAvatar,
    this.price = '免费',
    this.description = '',
    this.tags = const [],
    this.approval = false,
    this.isJoined = false,
    this.isOwned = false,
    this.startsAt,
    this.endsAt,
    this.beginnerFriendly = false,
    this.coverUrl,
    this.organizerRiskTag,
  });

  final int id;
  final String? apiId;
  final String emoji;
  final String title;
  final String category;
  final String time;
  final String area;
  final String distance;
  final String host;
  final String? organizerUserId;
  final String? organizerAvatar;
  final double hostScore;
  int joined;
  final int capacity;
  final String price;
  final String description;
  final List<String> tags;
  final bool approval;
  bool isJoined;
  final bool isOwned;
  final DateTime? startsAt;
  final DateTime? endsAt;
  bool get isPast => endsAt != null && !endsAt!.isAfter(DateTime.now());
  final bool beginnerFriendly;
  final String? coverUrl;
  final String? organizerRiskTag;
}

final demoEvents = <EventItem>[
  EventItem(
    id: 1,
    emoji: '🌿',
    title: '汉江日落野餐局',
    category: '户外',
    time: '今天 18:30',
    area: '汝矣岛 · 汉江公园',
    distance: '3.2 km',
    host: '小满',
    hostScore: 4.9,
    joined: 5,
    capacity: 8,
    description: '下班后来汉江吹吹风。我们会准备野餐垫和简单零食，你带喜欢的饮料就好。第一次参加也完全欢迎！',
    tags: ['20–35岁', '简中', '轻松社交'],
  ),
  EventItem(
    id: 2,
    emoji: '☕',
    title: '延南洞韩语口语交换',
    category: '语言',
    time: '明天 14:00',
    area: '弘大入口 · 延南洞',
    distance: '6.8 km',
    host: 'Eric',
    hostScore: 4.8,
    joined: 6,
    capacity: 6,
    price: '₩5,000',
    approval: true,
    description: '中文母语与韩语母语各半，每 20 分钟换一次话题。费用包含场地饮品。',
    tags: ['中韩交流', '需审核', '咖啡'],
  ),
  EventItem(
    id: 3,
    emoji: '🥾',
    title: '周六清晨北汉山轻徒步',
    category: '运动',
    time: '周六 08:00',
    area: '北汉山 · 九基洞',
    distance: '11 km',
    host: '阿泽',
    hostScore: 5.0,
    joined: 7,
    capacity: 10,
    description: '约 3 小时新手路线，途中会休息拍照。请穿防滑鞋并自备饮用水。',
    tags: ['新手友好', '户外', '准时出发'],
  ),
  EventItem(
    id: 4,
    emoji: '🎲',
    title: '江南下班后桌游夜',
    category: '桌游',
    time: '周五 19:30',
    area: '江南站 11号口',
    distance: '8.1 km',
    host: 'Nana',
    hostScore: 4.7,
    joined: 3,
    capacity: 8,
    price: 'AA制',
    description: '以轻策和欢乐桌游为主，不会规则也没关系，现场会教。',
    tags: ['下班搭子', '桌游', '不饮酒'],
  ),
];

typedef ActivityPageLoader =
    Future<ActivityPage> Function({
      double? latitude,
      double? longitude,
      String? city,
      String? district,
      required int limit,
      String? cursor,
    });

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialEvents,
    this.loadRemoteEvents = true,
    this.eventLoader,
  });

  final List<EventItem>? initialEvents;
  final bool loadRemoteEvents;
  final ActivityPageLoader? eventLoader;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _unread = 0;
  List<EventItem> _events = [];
  bool _eventsLoading = true;
  bool _eventsLoadFailed = false;
  static const _pageSize = 20;
  String? _nextEventCursor;
  bool _eventsRefreshing = false;
  int _eventGeneration = 0;
  bool _hasMoreEvents = false;
  bool _loadingMoreEvents = false;
  bool _moreEventsFailed = false;
  final Set<String> _loadedEventIds = {};
  double? _latitude;
  double? _longitude;
  String? _cityCode;
  String? _districtCode;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<void>? _pushSubscription;

  Future<bool> _selectHome() async {
    if (_index == 2 && !await _createKey.currentState!._confirmLeave()) {
      return false;
    }
    if (mounted) {
      setState(() {
        if (_index == 2) _createKey = GlobalKey<_CreateEventPageState>();
        _index = 0;
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    return true;
  }

  Future<void> _selectTab(int value) async {
    if (_index == 2 &&
        value != 2 &&
        !await _createKey.currentState!._confirmLeave()) {
      return;
    }
    if (mounted) {
      setState(() {
        if (_index == 2 && value != 2) {
          _createKey = GlobalKey<_CreateEventPageState>();
        }
        _index = value;
      });
      if (value == 3) await _loadUnread();
    }
  }

  GlobalKey<_CreateEventPageState> _createKey =
      GlobalKey<_CreateEventPageState>();

  @override
  void initState() {
    super.initState();
    _activeShell = this;
    _events = List<EventItem>.of(widget.initialEvents ?? const []);
    _eventsLoading = widget.loadRemoteEvents;
    if (widget.loadRemoteEvents || widget.eventLoader != null) _loadEvents();
    _realtimeSubscription = RealtimeService.instance.events.listen((_) {
      _loadUnread();
    });
    _pushSubscription = PushNotificationService.instance.events.listen((_) {
      _loadUnread();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadUnread();
      if (!mounted) return;
      final token = AuthScope.of(context).token;
      if (token == null) return;
      unawaited(RealtimeService.instance.start(token));
      unawaited(PushNotificationService.instance.start(token));
    });
  }

  Future<void> _loadUnread() async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      final summary = await SocialService.unreadSummary(token);
      if (mounted) setState(() => _unread = summary.total);
    } catch (_) {
      // Keep navigation usable when the message service is unavailable.
    }
  }

  @override
  void dispose() {
    if (identical(_activeShell, this)) _activeShell = null;
    _realtimeSubscription?.cancel();
    _pushSubscription?.cancel();
    unawaited(RealtimeService.instance.stop());
    super.dispose();
  }

  Future<void> _loadEvents() async {
    final generation = ++_eventGeneration;
    setState(() {
      _eventsRefreshing = _events.isNotEmpty;
      _eventsLoading = !_eventsRefreshing;
      _eventsLoadFailed = false;
      _loadingMoreEvents = false;
      _moreEventsFailed = false;
      _hasMoreEvents = false;
      _nextEventCursor = null;
      _loadedEventIds.clear();
    });
    await _fetchEventPage(generation, append: false);
  }

  Future<void> _loadMoreEvents() async {
    if (_eventsLoading ||
        _eventsRefreshing ||
        _loadingMoreEvents ||
        !_hasMoreEvents) {
      return;
    }
    setState(() {
      _loadingMoreEvents = true;
      _moreEventsFailed = false;
    });
    await _fetchEventPage(_eventGeneration, append: true);
  }

  Future<void> _fetchEventPage(int generation, {required bool append}) async {
    try {
      final page = await (widget.eventLoader ?? EventService.list)(
        latitude: _latitude,
        longitude: _longitude,
        city: _cityCode,
        district: _districtCode,
        limit: _pageSize,
        cursor: _nextEventCursor,
      );
      if (!mounted || generation != _eventGeneration) return;
      final rows = page.items;
      // Convert before mutating the cursor or deduplication state so retries
      // request the same page if a response cannot be rendered.
      final items = rows.map(_eventFromApi).toList();
      setState(() {
        if (!append) _events = [];
        for (var i = 0; i < rows.length; i++) {
          if (_loadedEventIds.add(rows[i]['id'].toString())) {
            _events.add(items[i]);
          }
        }
        _nextEventCursor = page.nextCursor;
        _hasMoreEvents = page.hasMore;
        _eventsLoading = false;
        _loadingMoreEvents = false;
        _eventsRefreshing = false;
      });
    } catch (_) {
      if (!mounted || generation != _eventGeneration) return;
      setState(() {
        _eventsLoading = false;
        _loadingMoreEvents = false;
        _eventsRefreshing = false;
        if (append) {
          _moreEventsFailed = true;
        } else {
          _eventsLoadFailed = true;
        }
      });
    }
  }

  Widget _paginationFooter() => _EventPaginationFooter(
    hasMore: _hasMoreEvents,
    loading: _loadingMoreEvents || _eventsRefreshing,
    failed: _moreEventsFailed,
    onLoadMore: _loadMoreEvents,
  );

  EventItem _eventFromApi(Map<String, dynamic> json) {
    final rawId = json['id'].toString();
    final startsAt = DateTime.tryParse('${json['starts_at']}')?.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    final time = startsAt == null
        ? '时间待定'
        : '${startsAt.month}月${startsAt.day}日 ${two(startsAt.hour)}:${two(startsAt.minute)}';
    final city = '${json['city_name'] ?? json['city_code'] ?? ''}';
    final district = '${json['district_name'] ?? json['district_code'] ?? ''}';
    final distanceMeters = json['distance_meters'] as num?;
    final priceAmount = (json['price_amount'] as num?)?.toInt() ?? 0;
    final currentUserId = AuthScope.of(context).user?.id;
    return EventItem(
      id: rawId.hashCode,
      apiId: rawId,
      emoji: '${json['category_icon'] ?? '✨'}',
      coverUrl: json['cover_url'] as String?,
      organizerRiskTag: json['organizer_risk_tag'] as String?,
      title: '${json['title'] ?? ''}',
      category: '${json['category_name'] ?? ''}',
      time: time,
      area: [city, district].where((value) => value.isNotEmpty).join(' · '),
      distance: distanceMeters == null
          ? '距离待计算'
          : '${(distanceMeters / 1000).toStringAsFixed(1)} km',
      host: '${json['organizer_name'] ?? '活动组织者'}',
      organizerUserId: json['organizer_user_id']?.toString(),
      organizerAvatar: json['organizer_avatar'] as String?,
      hostScore: (json['organizer_score'] as num?)?.toDouble() ?? 0,
      joined: (json['approved_count'] as num?)?.toInt() ?? 0,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      price: priceAmount == 0 ? '免费' : '预计 ₩$priceAmount/人',
      approval: json['approval_mode'] == 'manual',
      isOwned:
          currentUserId != null &&
          '${json['organizer_user_id']}' == currentUserId,
      description: '${json['description'] ?? ''}',
      startsAt: startsAt,
      endsAt: DateTime.tryParse('${json["ends_at"]}')?.toLocal(),
      beginnerFriendly:
          '${json['title'] ?? ''}'.contains('新手') ||
          '${json['description'] ?? ''}'.contains('新手') ||
          json['beginner_friendly'] == true,
      tags: [
        '${json['category_name'] ?? ''}',
        json['approval_mode'] == 'manual' ? '需审核' : '直接加入',
      ],
    );
  }

  void _openEvent(EventItem event) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailPage(
          event: event,
          onChanged: () => setState(() {}),
          onOpenMyActivities: () {
            final token = AuthScope.of(context).token;
            if (token == null) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MyActivitiesPage(token: token)),
            );
          },
        ),
      ),
    );
  }

  void _created(EventItem event) {
    setState(() {
      _events.insert(0, event);
      _index = 0;
    });
    _loadEvents();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('活动发布成功，已生成活动群聊')));
  }

  void _locationChanged(AppLocation location) {
    final changed =
        _latitude != location.latitude ||
        _longitude != location.longitude ||
        _cityCode != location.cityCode ||
        _districtCode != location.districtCode;
    if (!changed) return;
    _latitude = location.latitude;
    _longitude = location.longitude;
    _cityCode = location.cityCode;
    _districtCode = location.districtCode;
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        events: _events,
        onOpen: _openEvent,
        onLocationChanged: _locationChanged,
        loading: _eventsLoading,
        loadFailed: _eventsLoadFailed,
        onRetry: _loadEvents,
        onRefresh: _loadEvents,
        footer: widget.loadRemoteEvents || widget.eventLoader != null
            ? _paginationFooter()
            : null,
      ),
      DiscoverPage(
        events: _events,
        onOpen: _openEvent,
        loading: _eventsLoading,
        loadFailed: _eventsLoadFailed,
        onRetry: _loadEvents,
        onRefresh: _loadEvents,
        footer: widget.loadRemoteEvents || widget.eventLoader != null
            ? _paginationFooter()
            : null,
      ),
      CreateEventPage(
        key: _createKey,
        onCreated: _created,
        loadRemoteData: widget.loadRemoteEvents,
      ),
      MessagesPage(onUnreadChanged: _loadUnread),
      const ProfilePage(),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if ((_index == 0 || _index == 1) &&
                notification.depth == 0 &&
                notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) > 0 &&
                notification.metrics.extentAfter < 240 &&
                !_moreEventsFailed) {
              _loadMoreEvents();
            }
            return false;
          },
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: _FloatingDock(
        selectedIndex: _index,
        unread: _unread,
        labels: [
          context.tr('home'),
          context.tr('discover'),
          context.tr('create'),
          context.tr('messages'),
          context.tr('profile'),
        ],
        onSelected: _selectTab,
      ),
    );
  }
}

class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.selectedIndex,
    required this.unread,
    required this.labels,
    required this.onSelected,
  });

  final int selectedIndex;
  final int unread;
  final List<String> labels;
  final ValueChanged<int> onSelected;

  static const _icons = [
    Icons.home_rounded,
    Icons.explore_rounded,
    Icons.add_rounded,
    Icons.chat_bubble_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFDDE1EE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A29264A),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (index) {
              final selected = selectedIndex == index;
              final isCreate = index == 2;
              final icon = index == 3 && unread > 0
                  ? Badge(label: Text('$unread'), child: Icon(_icons[index]))
                  : Icon(_icons[index]);
              return Semantics(
                button: true,
                selected: selected,
                label: labels[index],
                child: InkWell(
                  key: Key('main-nav-$index'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: isCreate ? 58 : (selected ? 82 : 50),
                    height: isCreate ? 58 : 46,
                    transform: Matrix4.translationValues(
                      0,
                      isCreate ? -13 : 0,
                      0,
                    ),
                    decoration: BoxDecoration(
                      gradient: isCreate
                          ? const LinearGradient(
                              colors: [_orange, Color(0xFFFF8D72)],
                            )
                          : null,
                      color: isCreate
                          ? null
                          : (selected ? _mint : Colors.transparent),
                      borderRadius: BorderRadius.circular(isCreate ? 20 : 17),
                      boxShadow: isCreate
                          ? const [
                              BoxShadow(
                                color: Color(0x40FF6B57),
                                blurRadius: 16,
                                offset: Offset(0, 7),
                              ),
                            ]
                          : null,
                    ),
                    child: isCreate
                        ? const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 31,
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconTheme(
                                data: IconThemeData(
                                  color: selected
                                      ? _green
                                      : const Color(0xFF74768A),
                                  size: 23,
                                ),
                                child: icon,
                              ),
                              if (selected) ...[
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    labels[index],
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: const TextStyle(
                                      color: _green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class PagePadding extends StatelessWidget {
  const PagePadding({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), child: child);
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.events,
    required this.onOpen,
    required this.onRetry,
    this.footer,
    this.onRefresh,
    this.onLocationChanged,
    this.loading = false,
    this.loadFailed = false,
    super.key,
  });
  final List<EventItem> events;
  final ValueChanged<EventItem> onOpen;
  final VoidCallback onRetry;
  final Future<void> Function()? onRefresh;
  final Widget? footer;
  final ValueChanged<AppLocation>? onLocationChanged;
  final bool loading;
  final bool loadFailed;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocationService _locationService = LocationService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedFilters = {'附近热门'};
  String _locationLabel = '正在定位…';
  bool _locating = true;
  bool _hasResolvedLocation = false;
  bool _manualLocation = false;
  String? _locationLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (_locationLanguage == language) return;
    _locationLanguage = language;
    _restoreLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EventItem> get _visibleEvents {
    final query = _searchController.text.trim().toLowerCase();
    final events = widget.events.where((event) {
      final searchable = [
        event.title,
        event.area,
        event.category,
        event.description,
        event.host,
        ...event.tags,
      ].join(' ').toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      if (_selectedFilters.contains('今天') && !_isToday(event)) {
        return false;
      }
      if (_selectedFilters.contains('周末') && !_isWeekend(event)) {
        return false;
      }
      if (_selectedFilters.contains('新手友好') &&
          !event.beginnerFriendly &&
          !event.tags.contains('新手友好')) {
        return false;
      }
      if (_selectedFilters.contains('附近热门') && !_isNearby(event)) {
        return false;
      }
      return true;
    }).toList();
    return events;
  }

  double _distanceKilometers(String value) =>
      double.tryParse(RegExp(r'[\d.]+').firstMatch(value)?.group(0) ?? '') ??
      double.infinity;

  bool _isToday(EventItem event) {
    final startsAt = event.startsAt;
    if (startsAt == null) return event.time.startsWith('今天');
    final now = DateTime.now();
    return startsAt.year == now.year &&
        startsAt.month == now.month &&
        startsAt.day == now.day;
  }

  bool _isWeekend(EventItem event) {
    final startsAt = event.startsAt;
    if (startsAt == null) {
      return event.time.startsWith('周六') || event.time.startsWith('周日');
    }
    return startsAt.weekday == DateTime.saturday ||
        startsAt.weekday == DateTime.sunday;
  }

  bool _isNearby(EventItem event) {
    if (_locating || !_hasResolvedLocation) return true;
    final distance = _distanceKilometers(event.distance);
    if (distance.isFinite) return distance <= 10;
    final locationParts = _locationLabel
        .split(' · ')
        .map((part) => part.trim())
        .where((part) => part.length >= 2);
    return locationParts.any(event.area.contains);
  }

  void _toggleFilter(String filter) {
    setState(() {
      if (!_selectedFilters.add(filter)) _selectedFilters.remove(filter);
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(_selectedFilters.clear);
  }

  Future<void> _restoreLocation() async {
    final saved = await _locationService.readManualRegion();
    if (!mounted || saved == null) {
      if (mounted) await _locate(forceRefresh: true, offerManual: true);
      return;
    }
    try {
      final regions = await RegionService.load();
      if (!mounted) return;
      final location = _manualAppLocation(saved, regions);
      if (location == null) {
        await _locationService.clearManualRegion();
        await _locate(forceRefresh: true, offerManual: true);
        return;
      }
      _applyLocation(location);
    } catch (_) {
      if (mounted) await _locate(forceRefresh: true, offerManual: true);
    }
  }

  AppLocation? _manualAppLocation(
    ManualRegionSelection selection,
    List<AdministrativeRegion> regions,
  ) {
    AdministrativeRegion? city;
    AdministrativeRegion? district;
    for (final region in regions) {
      if (region.code == selection.cityCode && region.level == 1) city = region;
      if (region.code == selection.districtCode) district = region;
    }
    if (city == null) return null;
    final language = _locationLanguage ?? 'zh';
    final label = [
      city.displayName(language),
      if (district != null) district.displayName(language),
    ].join(' · ');
    return AppLocation(
      label: label,
      cityCode: city.code,
      districtCode: district?.code,
    );
  }

  void _applyLocation(AppLocation location) {
    setState(() {
      _locationLabel = location.label;
      _hasResolvedLocation = true;
      _manualLocation = location.isManual;
      _locating = false;
    });
    widget.onLocationChanged?.call(location);
  }

  Future<void> _locate({
    bool forceRefresh = false,
    bool offerManual = false,
  }) async {
    setState(() {
      _locating = true;
      if (forceRefresh) {
        _locationLabel = '正在定位…';
        _hasResolvedLocation = false;
      }
    });
    try {
      final location = await _locationService.locate(
        languageCode: _locationLanguage ?? 'zh',
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      await _locationService.clearManualRegion();
      if (!mounted) return;
      _applyLocation(location);
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(() => _locationLabel = error.message);
      if (offerManual) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _chooseManualLocation();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationLabel = context.tr('locationFailed'));
      if (offerManual) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _chooseManualLocation();
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showLocationOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(context.tr('useAutomaticLocation')),
              onTap: () => Navigator.pop(context, 'automatic'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(context.tr('chooseLocationManually')),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'automatic') {
      await _locate(forceRefresh: true, offerManual: true);
    } else if (action == 'manual') {
      await _chooseManualLocation();
    }
  }

  Future<void> _chooseManualLocation() async {
    List<AdministrativeRegion> regions;
    try {
      regions = await RegionService.load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('regionsLoadFailed'))));
      return;
    }
    if (!mounted) return;
    final saved = await _locationService.readManualRegion();
    if (!mounted) return;
    final selection = await showModalBottomSheet<ManualRegionSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ManualLocationSheet(
        regions: regions,
        languageCode: _locationLanguage ?? 'zh',
        initialSelection: saved,
      ),
    );
    if (!mounted || selection == null) return;
    final location = _manualAppLocation(selection, regions);
    if (location == null) return;
    await _locationService.saveManualRegion(selection);
    if (!mounted) return;
    _applyLocation(location);
  }

  @override
  Widget build(BuildContext context) {
    final list = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: PagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: _locating ? null : _showLocationOptions,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_locating)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 7),
                                      child: Icon(
                                        Icons.location_searching,
                                        size: 15,
                                        color: _green,
                                      ),
                                    )
                                  else
                                    Padding(
                                      padding: EdgeInsets.only(right: 5),
                                      child: Icon(
                                        _manualLocation
                                            ? Icons.location_on_outlined
                                            : Icons.my_location,
                                        size: 15,
                                        color: _green,
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      _locationLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.expand_more, size: 16),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '今天，找个搭子',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _showNotice(context),
                      icon: const Badge(
                        smallSize: 8,
                        child: Icon(Icons.notifications_none_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B4BDB), Color(0xFF7668EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x335B4BDB),
                        blurRadius: 28,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.radar_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            '附近正在发生',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Color(0xFFFFD3CC),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('home-search-field'),
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜一个现在想做的事',
                          prefixIcon: const Icon(Icons.search, color: _green),
                          suffixIcon: _searchController.text.isEmpty
                              ? const Icon(Icons.tune_rounded, size: 20)
                              : IconButton(
                                  tooltip: '清除搜索',
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const ['附近热门', '今天', '周末', '新手友好']
                      .map(
                        (filter) => FilterChipLabel(
                          filter == '附近热门' ? '🔥 $filter' : filter,
                          selected: _selectedFilters.contains(filter),
                          onTap: () => _toggleFilter(filter),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF211F42), Color(0xFF34305F)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0x22FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '第一次参加？',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '从 2–8 人的小活动开始\n见面前可开启安全会面',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .72),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: _orange,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Text('👋', style: TextStyle(fontSize: 34)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SectionTitle(
                  title: '为你推荐 · ${_visibleEvents.length}',
                  action:
                      _searchController.text.isNotEmpty ||
                          _selectedFilters.isNotEmpty
                      ? '清除筛选'
                      : null,
                  onAction: _clearFilters,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          sliver: widget.loading
              ? const SliverToBoxAdapter(child: _EventListSkeleton())
              : widget.loadFailed
              ? SliverToBoxAdapter(child: LoadFailure(onRetry: widget.onRetry))
              : _visibleEvents.isEmpty
              ? SliverToBoxAdapter(child: _EmptySearch(onClear: _clearFilters))
              : SliverList.separated(
                  itemCount: _visibleEvents.length,
                  itemBuilder: (_, index) => EventCard(
                    event: _visibleEvents[index],
                    onTap: () => widget.onOpen(_visibleEvents[index]),
                  ),
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                ),
        ),
        if (!widget.loading && !widget.loadFailed && widget.footer != null)
          SliverToBoxAdapter(child: widget.footer!),
      ],
    );
    return widget.onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
  }

  void _showNotice(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '通知',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _mint,
                  child: Icon(Icons.how_to_reg),
                ),
                title: Text('报名已通过'),
                subtitle: Text('汉江日落野餐局 · 记得按时到达'),
                trailing: Text('刚刚'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualLocationSheet extends StatefulWidget {
  const _ManualLocationSheet({
    required this.regions,
    required this.languageCode,
    this.initialSelection,
  });

  final List<AdministrativeRegion> regions;
  final String languageCode;
  final ManualRegionSelection? initialSelection;

  @override
  State<_ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<_ManualLocationSheet> {
  String? _cityCode;
  String? _districtCode;

  List<AdministrativeRegion> get _cities =>
      widget.regions.where((region) => region.level == 1).toList();

  List<AdministrativeRegion> get _districts =>
      widget.regions.where((region) => region.parentCode == _cityCode).toList();

  @override
  void initState() {
    super.initState();
    final cities = _cities;
    final initialCity = widget.initialSelection?.cityCode;
    _cityCode = cities.any((city) => city.code == initialCity)
        ? initialCity
        : (cities.isEmpty ? null : cities.first.code);
    final districts = _districts;
    final initialDistrict = widget.initialSelection?.districtCode;
    _districtCode =
        districts.any((district) => district.code == initialDistrict)
        ? initialDistrict
        : (districts.isEmpty ? null : districts.first.code);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('chooseLocationManually'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('manualLocationHint'),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _cityCode,
            decoration: InputDecoration(labelText: context.tr('city')),
            items: _cities
                .map(
                  (city) => DropdownMenuItem(
                    value: city.code,
                    child: Text(city.displayName(widget.languageCode)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _cityCode = value;
              final districts = _districts;
              _districtCode = districts.isEmpty ? null : districts.first.code;
            }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey(_cityCode),
            initialValue: _districtCode,
            decoration: InputDecoration(labelText: context.tr('district')),
            items: _districts
                .map(
                  (district) => DropdownMenuItem(
                    value: district.code,
                    child: Text(district.displayName(widget.languageCode)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _districtCode = value),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _cityCode == null
                ? null
                : () => Navigator.pop(
                    context,
                    ManualRegionSelection(
                      cityCode: _cityCode!,
                      districtCode: _districtCode,
                    ),
                  ),
            icon: const Icon(Icons.check),
            label: Text(context.tr('useSelectedLocation')),
          ),
        ],
      ),
    ),
  );
}

class FilterChipLabel extends StatelessWidget {
  const FilterChipLabel(
    this.label, {
    this.selected = false,
    required this.onTap,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _mint : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _green : const Color(0xFFE5E3DD),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _green : _ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
    alignment: Alignment.center,
    child: Column(
      children: [
        const Icon(Icons.search_off_rounded, size: 46, color: Colors.black38),
        const SizedBox(height: 12),
        const Text(
          '没有找到符合条件的活动',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text('试试其他关键词，或者减少筛选条件'),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onClear, child: const Text('清除全部筛选')),
      ],
    ),
  );
}

class _EventListSkeleton extends StatelessWidget {
  const _EventListSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 14),
          Text('正在加载活动…', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class EventCard extends StatelessWidget {
  const EventCard({required this.event, required this.onTap, super.key});
  final EventItem event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 92,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: event.id.isEven
                      ? const [Color(0xFFFFE7D6), Color(0xFFFFF7EC)]
                      : const [Color(0xFFDCEFE4), Color(0xFFF4F1D5)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: event.coverUrl == null
                  ? Text(event.emoji, style: const TextStyle(fontSize: 42))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        absoluteImageUrl(event.coverUrl!),
                        width: 92,
                        height: 112,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Text(
                          event.emoji,
                          style: const TextStyle(fontSize: 42),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (event.isJoined)
                        const Icon(Icons.check_circle, color: _green, size: 19),
                    ],
                  ),
                  if (event.isPast) _Pill(context.tr('pastActivity')),
                  if (event.organizerRiskTag != null) ...[
                    const SizedBox(height: 7),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _RiskPill(
                        text: feedbackTagLabel(
                          context,
                          event.organizerRiskTag!,
                        ),
                      ),
                    ),
                  ],
                  if (event.isOwned) ...[
                    const SizedBox(height: 7),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: _Pill('我发布的', green: true),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    event.time,
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${event.area} · ${event.distance}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${event.joined}/${event.capacity} 人',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        event.price,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    required this.events,
    required this.onOpen,
    this.footer,
    this.loading = false,
    this.loadFailed = false,
    this.onRetry,
    this.onRefresh,
    super.key,
  });
  final Future<void> Function()? onRefresh;
  final Widget? footer;
  final bool loading;
  final bool loadFailed;
  final VoidCallback? onRetry;
  final List<EventItem> events;
  final ValueChanged<EventItem> onOpen;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  bool _map = false;
  String _category = '全部';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.events
        .where(
          (e) =>
              (_category == '全部' || e.category == _category) &&
              (e.title.contains(_search.text) || e.area.contains(_search.text)),
        )
        .toList();
    return Column(
      children: [
        PagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('发现', style: Theme.of(context).textTheme.headlineLarge),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.map_outlined),
                      ),
                    ],
                    selected: {_map},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _map = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索活动或地点',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ['全部', '户外', '语言', '运动', '桌游'].map((label) {
                    final selected = _category == label;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: selected,
                        onSelected: (_) => setState(() => _category = label),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.loading
              ? const _EventListSkeleton()
              : widget.loadFailed
              ? LoadFailure(onRetry: widget.onRetry ?? () {})
              : _map
              ? MapPlaceholder(events: visible, onOpen: widget.onOpen)
              : RefreshIndicator(
                  onRefresh: widget.onRefresh ?? () async {},
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: visible.length + (widget.footer == null ? 0 : 1),
                    itemBuilder: (_, i) => i == visible.length
                        ? widget.footer!
                        : EventCard(
                            event: visible[i],
                            onTap: () => widget.onOpen(visible[i]),
                          ),
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EventPaginationFooter extends StatelessWidget {
  const _EventPaginationFooter({
    required this.hasMore,
    required this.loading,
    required this.failed,
    required this.onLoadMore,
  });
  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    child: Column(
      children: [
        if (hasMore)
          Text(context.tr('paginationFilterHint'), textAlign: TextAlign.center),
        if (failed)
          Text(context.tr('paginationFailed'), textAlign: TextAlign.center),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          )
        else if (hasMore)
          OutlinedButton(
            onPressed: onLoadMore,
            child: Text(context.tr(failed ? 'retry' : 'loadMore')),
          )
        else
          Text(context.tr('paginationEnd')),
      ],
    ),
  );
}

class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({required this.events, required this.onOpen, super.key});
  final List<EventItem> events;
  final ValueChanged<EventItem> onOpen;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E8DE),
          borderRadius: BorderRadius.circular(24),
        ),
        child: CustomPaint(
          painter: _MapPainter(),
          child: const SizedBox.expand(),
        ),
      ),
      ...events.take(4).toList().asMap().entries.map((entry) {
        final positions = [
          const Offset(.25, .25),
          const Offset(.65, .18),
          const Offset(.55, .52),
          const Offset(.22, .66),
        ];
        final pos = positions[entry.key];
        return Positioned(
          left: MediaQuery.sizeOf(context).width * pos.dx,
          top: MediaQuery.sizeOf(context).height * pos.dy * .55,
          child: GestureDetector(
            onTap: () => onOpen(entry.value),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: _green,
                shape: BoxShape.circle,
              ),
              child: Text(
                entry.value.emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        );
      }),
      Positioned(
        left: 35,
        right: 35,
        bottom: 40,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.privacy_tip_outlined, color: _green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '公开地图仅显示区域范围，报名通过后才展示准确集合点',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height * .35),
      Offset(size.width, size.height * .58),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .3, 0),
      Offset(size.width * .42, size.height),
      road,
    );
    canvas.drawLine(
      Offset(0, size.height * .78),
      Offset(size.width, size.height * .2),
      road,
    );
    final river = Paint()
      ..color = const Color(0xFFAEDBE7)
      ..strokeWidth = 35
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height * .55),
      Offset(size.width, size.height * .82),
      river,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class EventDetailPage extends StatefulWidget {
  const EventDetailPage({
    required this.event,
    required this.onChanged,
    required this.onOpenMyActivities,
    super.key,
  });
  final EventItem event;
  final VoidCallback onChanged;
  final VoidCallback onOpenMyActivities;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  bool _saved = false;
  bool _joining = false;
  bool _detailStarted = false;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _members = const [];
  String? _membershipStatus;
  FeedbackEligibilityData? _feedback;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_detailStarted && widget.event.apiId != null) {
      _detailStarted = true;
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    final token = AuthScope.of(context).token;
    if (token == null || widget.event.apiId == null) return;
    try {
      final detail = await EventService.detailData(token, widget.event.apiId!);
      if (!mounted) return;
      setState(() {
        _detail = detail.item;
        _members = detail.members;
        _feedback = detail.feedback;
        _membershipStatus = detail.item['viewer_membership_status']?.toString();
        widget.event.joined =
            (detail.item['approved_count'] as num?)?.toInt() ??
            widget.event.joined;
        widget.event.isJoined =
            _membershipStatus == 'approved' || _membershipStatus == 'attended';
      });
      widget.onChanged();
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final full = e.joined >= e.capacity;
    final cancelled = _detail?['status'] == 'cancelled';
    final originalCoverUrl = _detail?['cover_original_url']?.toString();
    final canOpenOriginal =
        originalCoverUrl != null && originalCoverUrl.isNotEmpty;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            expandedHeight: 235,
            pinned: true,
            backgroundColor: _mint,
            actions: [
              IconButton.filledTonal(
                onPressed: () => setState(() => _saved = !_saved),
                icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
              ),
              const _HomeAction(),
              const SizedBox(width: 12),
            ],
            leading: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD7ECDF), Color(0xFFFFEED9)],
                  ),
                ),
                child: e.coverUrl == null
                    ? Text(e.emoji, style: const TextStyle(fontSize: 84))
                    : GestureDetector(
                        onTap: canOpenOriginal
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ChatImagePreviewPage(
                                    imageUrl: absoluteImageUrl(
                                      originalCoverUrl,
                                    ),
                                    titleKey: 'eventCoverPreview',
                                    heroTag: 'event-cover-$originalCoverUrl',
                                  ),
                                ),
                              )
                            : null,
                        child: Image.network(
                          absoluteImageUrl(e.coverUrl!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, _, _) => Text(
                            e.emoji,
                            style: const TextStyle(fontSize: 84),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      _Pill(e.category),
                      if (cancelled) _Pill(context.tr('eventCancelled')),
                      if (e.isPast) _Pill(context.tr('pastActivity')),
                      if (e.isOwned) const _Pill('我发布的', green: true),
                      if (e.approval) const _Pill('需组织者审核'),
                      if (e.isJoined && !e.isOwned)
                        const _Pill('已参加', green: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    e.title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (cancelled)
                    EventCancellationNotice(
                      reason: '${_detail?['cancellation_reason'] ?? ''}',
                    ),
                  const SizedBox(height: 24),
                  _DetailRow(
                    icon: Icons.schedule,
                    title: e.time,
                    subtitle: '活动开始前 1 小时提醒',
                  ),
                  _DetailRow(
                    icon: Icons.location_on_outlined,
                    title: e.area,
                    subtitle: '报名通过后显示准确集合点',
                  ),
                  _DetailRow(
                    icon: Icons.payments_outlined,
                    title: e.price,
                    subtitle: e.price == '免费' ? '无需支付费用' : '活动现场结算',
                  ),
                  const Divider(height: 34),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: _organizerUserId == null
                        ? null
                        : () => _openPublicProfile(
                            context,
                            _organizerUserId!,
                            eventId: e.apiId,
                          ),
                    leading: UserAvatarImage(
                      nickname: e.host,
                      avatarUrl:
                          _detail?['organizer_avatar'] as String? ??
                          e.organizerAvatar,
                      radius: 25,
                    ),
                    title: Text(
                      '组织者 · ${e.host}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('信誉 ${e.hostScore} · 已组织 12 场 · 回复迅速'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '活动介绍',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    e.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: e.tags.map((t) => _Pill(t)).toList(),
                  ),
                  if (e.isPast && e.apiId != null && !cancelled)
                    FeedbackActionGrid(
                      token: AuthScope.of(context).token ?? '',
                      eventId: e.apiId!,
                      targetType: 'activity',
                      initialEligibility: _feedback,
                      onPublishSimilar: () =>
                          _openSimilarEvent(context, e.apiId!),
                    ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Text(
                        '参加成员',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${e.joined}/${e.capacity} 人',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_members.isEmpty)
                    const Text('暂无已通过的参加成员')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _members
                          .map(
                            (member) => InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => _openPublicProfile(
                                context,
                                '${member['user_id']}',
                                eventId: e.apiId,
                              ),
                              child: UserAvatarImage(
                                nickname: '${member['nickname'] ?? '用户'}',
                                avatarUrl: member['avatar_url'] as String?,
                                radius: 20,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _mint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: _green),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '安心见面',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: 4),
                              Text('首次见面建议选择公共场所，并开启定时确认。遇到紧急情况请立即联系当地警方。'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              IconButton.outlined(
                onPressed: () {},
                icon: const Icon(Icons.ios_share),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed:
                      cancelled ||
                          _joining ||
                          (e.isPast && !e.isOwned) ||
                          (_membershipStatus != null && !_canLeave) ||
                          (!e.approval && full && !e.isOwned && !_canLeave)
                      ? null
                      : e.isOwned
                      ? widget.onOpenMyActivities
                      : _canLeave
                      ? () => _leave(e)
                      : () => _join(e),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: _canLeave && !e.isOwned
                        ? Colors.grey.shade700
                        : _green,
                  ),
                  child: _joining
                      ? const _ButtonProgress(label: '提交中…')
                      : Text(
                          cancelled
                              ? context.tr('eventCancelled')
                              : e.isOwned
                              ? '查看我的活动'
                              : e.isPast
                              ? context.tr('pastActivity')
                              : _canLeave
                              ? '退出活动'
                              : _membershipLabel ??
                                    (e.approval
                                        ? '申请参加'
                                        : full
                                        ? '人数已满'
                                        : '立即参加'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _organizerUserId =>
      _detail?['organizer_user_id']?.toString() ?? widget.event.organizerUserId;

  bool get _canLeave =>
      _membershipStatus == 'approved' ||
      _membershipStatus == 'attended' ||
      _membershipStatus == 'waitlisted';

  String? get _membershipLabel => switch (_membershipStatus) {
    'applied' => '申请审核中',
    'rejected' => '申请未通过',
    'withdrawn' => '已退出活动',
    'waitlisted' => '候补中',
    _ => null,
  };

  Future<void> _join(EventItem e) async {
    final eventId = e.apiId;
    if (eventId == null) {
      setState(() {
        _membershipStatus = 'approved';
        e.isJoined = true;
        e.joined++;
      });
      widget.onChanged();
      _showJoinResult('approved');
      return;
    }
    final token = AuthScope.of(context).token;
    if (token == null) {
      _showMessageError(context, '该活动暂时无法报名，请刷新后重试');
      return;
    }
    final note = e.approval ? await _askApplicationNote() : '';
    if (note == null || !mounted) return;
    setState(() => _joining = true);
    Map<String, dynamic> member;
    try {
      member = await EventService.join(token, eventId, note: note);
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
      if (mounted) setState(() => _joining = false);
      return;
    }
    if (!mounted) return;
    final status = '${member['status']}';
    setState(() {
      _joining = false;
      _membershipStatus = status;
      if (status == 'approved') {
        e.isJoined = true;
        e.joined++;
      }
    });
    widget.onChanged();
    _showJoinResult(status);
  }

  void _showJoinResult(String status) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: _mint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                status == 'waitlisted' ? Icons.hourglass_top : Icons.check,
                color: _green,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              status == 'waitlisted'
                  ? '已加入候补'
                  : status == 'applied'
                  ? '申请已提交'
                  : '参加成功！',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              status == 'waitlisted'
                  ? '有名额释放时会按顺序自动递补并通知你'
                  : status == 'applied'
                  ? '组织者审核后会通过站内消息通知你'
                  : '活动群聊已解锁，可在「消息」中查看',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askApplicationNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('申请参加'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '申请备注（选填）',
            hintText: '可以简单介绍自己或说明参加原因',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('提交申请'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _leave(EventItem e) async {
    final eventId = e.apiId;
    final token = AuthScope.of(context).token;
    if (eventId == null || token == null || _joining) return;
    setState(() => _joining = true);
    try {
      await EventService.leave(token, eventId);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _membershipStatus = 'withdrawn';
        if (e.isJoined) e.joined = (e.joined - 1).clamp(0, e.capacity);
        e.isJoined = false;
      });
      widget.onChanged();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出活动')));
    } catch (error) {
      if (mounted) {
        setState(() => _joining = false);
        _showMessageError(context, '$error');
      }
    }
  }
}

void _openPublicProfile(
  BuildContext context,
  String userId, {
  String? eventId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PublicUserProfilePage(userId: userId, eventId: eventId),
    ),
  );
}

class UserAvatarImage extends StatelessWidget {
  const UserAvatarImage({
    required this.nickname,
    required this.radius,
    this.avatarUrl,
    super.key,
  });

  final String nickname;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final fallback = nickname.trim().isEmpty ? '用' : nickname.trim()[0];
    return CircleAvatar(
      radius: radius,
      backgroundColor: _mint,
      child: url == null || url.isEmpty
          ? Text(fallback, style: TextStyle(fontSize: radius * .75))
          : ClipOval(
              child: Image.network(
                absoluteImageUrl(url),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(child: Text(fallback)),
              ),
            ),
    );
  }
}

class PublicUserProfilePage extends StatefulWidget {
  const PublicUserProfilePage({required this.userId, this.eventId, super.key});

  final String userId;
  final String? eventId;

  @override
  State<PublicUserProfilePage> createState() => _PublicUserProfilePageState();
}

class _PublicUserProfilePageState extends State<PublicUserProfilePage> {
  Future<Map<String, dynamic>>? _future;
  bool _countedLikeSubmission = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<Map<String, dynamic>> _load() => EventService.publicProfile(
    widget.userId,
    token: AuthScope.of(context).token,
    eventId: widget.eventId,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('用户信息'), actions: const [_HomeAction()]),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => setState(() => _future = _load()),
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          );
        }
        final profile = snapshot.data!;
        final nickname = '${profile['nickname'] ?? '用户'}';
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: context.tr('viewAvatar'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(52),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AvatarPreviewPage(
                          nickname: nickname,
                          avatarUrl: profile['avatar_url'] as String?,
                        ),
                      ),
                    ),
                    child: UserAvatarImage(
                      nickname: nickname,
                      avatarUrl: profile['avatar_url'] as String?,
                      radius: 52,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  nickname,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '❤ ${profile['like_count'] ?? 0}',
                  style: const TextStyle(
                    color: Colors.pink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (profile['positive_tags'] is List &&
                    (profile['positive_tags'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: (profile['positive_tags'] as List)
                        .map(
                          (tag) => _Pill(
                            feedbackTagLabel(context, '${tag['tag_code']}'),
                            green: true,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (widget.eventId != null &&
                    profile['feedback_eligible'] == true)
                  FeedbackActionGrid(
                    token: AuthScope.of(context).token ?? '',
                    eventId: widget.eventId!,
                    targetType: 'user',
                    targetUserId: widget.userId,
                    initialEligibility: FeedbackEligibilityData(
                      eligible: true,
                      likeTag: profile['viewer_like_tag'] as String?,
                      reportTag: profile['viewer_report_tag'] as String?,
                    ),
                    onLikeSubmitted: () {
                      if (profile['viewer_like_tag'] == null &&
                          !_countedLikeSubmission) {
                        setState(() {
                          _countedLikeSubmission = true;
                          profile['like_count'] =
                              ((profile['like_count'] as num?)?.toInt() ?? 0) +
                              1;
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.green = false});
  final String text;
  final bool green;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: green ? _mint : const Color(0xFFF0EFEA),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: green ? _green : _ink,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.orange.shade300),
    ),
    child: Text(
      '${context.tr('riskSignal')}: $text',
      style: TextStyle(
        color: Colors.orange.shade900,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 17),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: _green),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({
    required this.onCreated,
    this.loadRemoteData = true,
    this.sourceEventId,
    super.key,
  });
  final String? sourceEventId;
  final ValueChanged<EventItem> onCreated;
  final bool loadRemoteData;

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  bool _allowLeave = false;
  bool _selectionEdited = false;

  bool get _hasDraft =>
      _title.text.trim().isNotEmpty ||
      _description.text.trim().isNotEmpty ||
      _customSubcategory.text.trim().isNotEmpty ||
      _coverBytes != null ||
      _meetingPoint.text.trim().isNotEmpty ||
      _price.text != '0' ||
      _startsAt != null ||
      _endsAt != null ||
      _step != 0 ||
      _capacity != 6 ||
      !_approval ||
      _selectionEdited ||
      _sourceId != null;

  Future<bool> _confirmLeave() async {
    if (_allowLeave || !_hasDraft) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('discardDraftTitle')),
        content: Text(dialogContext.tr('discardDraftMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.tr('discardDraft')),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _allowLeave = true);
      await WidgetsBinding.instance.endOfFrame;
    }
    return leave == true;
  }

  bool _loadingSource = false;
  bool _sourceFailed = false;
  bool _sourceInitialized = false;
  String? _sourceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sourceInitialized) {
      _sourceInitialized = true;
      if (widget.sourceEventId != null) _loadSource(widget.sourceEventId!);
    }
  }

  Future<void> _loadSource(String id) async {
    setState(() {
      _sourceId = id;
      _loadingSource = true;
      _sourceFailed = false;
    });
    try {
      final auth = AuthScope.of(context);
      final data = await EventService.detail(auth.token!, id);
      final categories = await _categoryFuture;
      final regions = await _regionFuture;
      if (!mounted) return;
      if (data['organizer_user_id'] != auth.user?.id) {
        throw const EventServiceException('');
      }
      final category = categories.where((c) => c.id == data['category_id']);
      setState(() {
        _title.text = data['title'] as String? ?? '';
        _description.text = data['description'] as String? ?? '';
        _leafCategoryId = category.isEmpty ? null : category.first.id;
        _majorCategoryId = category.isEmpty ? null : category.first.parentId;
        _customSubcategory.text = data['custom_subcategory'] as String? ?? '';
        _cityCode = regions.any((r) => r.code == data['city_code'])
            ? data['city_code'] as String
            : null;
        _districtCode = regions.any((r) => r.code == data['district_code'])
            ? data['district_code'] as String
            : null;
        _meetingPoint.text = data['place_name'] as String? ?? '';
        _price.text = '${data['price_amount'] ?? 0}';
        _capacity = (data['capacity'] as num).toInt();
        _approval = data['approval_mode'] == 'manual';
        _startsAt = null;
        _endsAt = null;
        _step = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _sourceFailed = true);
    } finally {
      if (mounted) setState(() => _loadingSource = false);
    }
  }

  Future<void> _chooseSource() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MyActivitiesPage(
          token: AuthScope.of(context).token!,
          selectSource: true,
        ),
      ),
    );
    if (id != null && mounted) await _loadSource(id);
  }

  int _step = 0;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _customSubcategory = TextEditingController();
  String _category = '户外';
  late Future<List<ActivityCategory>> _categoryFuture;
  late Future<List<AdministrativeRegion>> _regionFuture;
  String? _majorCategoryId;
  String? _leafCategoryId;
  bool _showMoreCategories = false;
  bool _otherSelected = false;
  int _capacity = 6;
  bool _approval = true;
  bool _publishing = false;
  Uint8List? _coverBytes;
  bool _coverBusy = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _cityCode;
  String? _districtCode;
  String _city = '';
  String _district = '';
  final _meetingPoint = TextEditingController();
  final _price = TextEditingController(text: '0');

  Future<void> _chooseCover() async {
    if (_coverBusy) return;
    setState(() => _coverBusy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      if (await picked.length() > 128 * 1024 * 1024) {
        throw const FormatException('largePhotoProcessingFailed');
      }
      if (!mounted) return;
      final webLayout = webCropperLayout(context);
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        maxWidth: 1600,
        maxHeight: 1200,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: context.tr('eventCoverCrop'),
            toolbarColor: _green,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: context.tr('eventCoverCrop'),
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
          WebUiSettings(
            context: context,
            presentStyle: webLayout.presentStyle,
            viewwMode: WebViewMode.mode_1,
            guides: true,
            rotatable: true,
            size: webLayout.size,
            translations: WebTranslations(
              title: context.tr('eventCoverCrop'),
              rotateLeftTooltip: context.tr('eventCoverRotateLeft'),
              rotateRightTooltip: context.tr('eventCoverRotateRight'),
              cancelButton: context.tr('eventCoverCancel'),
              cropButton: context.tr('eventCoverConfirmCrop'),
            ),
            themeData: const WebThemeData(rotateIconColor: _green),
          ),
        ],
      );
      if (cropped == null || !mounted) return;
      final bytes = prepareEventCover(await cropped.readAsBytes());
      if (mounted) setState(() => _coverBytes = bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? context.tr(error.message)
                  : context.tr('largePhotoProcessingFailed'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.sourceEventId != null) _activeRouteDraft = this;
    for (final controller in [
      _title,
      _description,
      _customSubcategory,
      _meetingPoint,
      _price,
    ]) {
      controller.addListener(_refreshLeaveGuard);
    }
    _categoryFuture = widget.loadRemoteData
        ? CategoryService.load()
        : Future.value(const []);
    _regionFuture = widget.loadRemoteData
        ? RegionService.load()
        : Future.value(const []);
  }

  void _refreshLeaveGuard() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (identical(_activeRouteDraft, this)) _activeRouteDraft = null;
    _title.dispose();
    _description.dispose();
    _customSubcategory.dispose();
    _meetingPoint.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowLeave || !_hasDraft,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _allowLeave || !_hasDraft) return;
      if (!await _confirmLeave() || !context.mounted) return;
      Navigator.of(context).pop();
    },
    child: _loadingSource
        ? const Center(child: CircularProgressIndicator())
        : _sourceFailed
        ? LoadFailure(
            onRetry: () {
              _categoryFuture = CategoryService.load();
              _regionFuture = RegionService.load();
              if (_sourceId != null) {
                _loadSource(_sourceId!);
              } else {
                setState(() => _sourceFailed = false);
                _chooseSource();
              }
            },
          )
        : Column(
            children: [
              PagePadding(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '发布活动',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    Text(
                      '${_step + 1}/3',
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(value: (_step + 1) / 3, minHeight: 3),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: [_basic(), _schedule(), _rules()][_step],
                  ),
                ),
              ),
              SafeArea(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      if (_step > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _step--),
                            child: const Text('上一步'),
                          ),
                        ),
                      if (_step > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _publishing ? null : _next,
                          child: _publishing
                              ? const _ButtonProgress(label: '发布中…')
                              : Text(_step == 2 ? '确认发布' : '下一步'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );

  Widget _basic() => Column(
    key: const ValueKey(0),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: _chooseSource,
        icon: const Icon(Icons.copy_outlined),
        label: Text(context.tr('createFromPrevious')),
      ),
      Text(context.tr('copyEventHint')),
      const SizedBox(height: 20),
      const Text(
        '先介绍一下活动',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text('清晰的主题更容易找到合适的搭子', style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 24),
      const FieldLabel('活动名称'),
      TextField(
        controller: _title,
        decoration: const InputDecoration(hintText: '例如：汉江日落野餐局'),
      ),
      const SizedBox(height: 20),
      FieldLabel(context.tr('eventCoverLabel')),
      Text(
        context.tr('eventCoverRule'),
        style: TextStyle(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 8),
      if (_coverBytes != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.memory(_coverBytes!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context
              .tr('eventCoverReady')
              .replaceFirst('{size}', '${(_coverBytes!.length / 1024).ceil()}'),
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _coverBusy ? null : _chooseCover,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              context.tr(
                _coverBytes == null ? 'eventCoverChoose' : 'eventCoverReplace',
              ),
            ),
          ),
          if (_coverBytes != null)
            TextButton.icon(
              onPressed: _coverBusy
                  ? null
                  : () => setState(
                      () => _coverBytes = flipEventCover(_coverBytes!),
                    ),
              icon: const Icon(Icons.flip),
              label: Text(context.tr('flipPhoto')),
            ),
          if (_coverBytes != null)
            TextButton(
              onPressed: _coverBusy
                  ? null
                  : () => setState(() => _coverBytes = null),
              child: Text(context.tr('eventCoverRemove')),
            ),
        ],
      ),
      const SizedBox(height: 20),
      const FieldLabel('活动分类'),
      FutureBuilder<List<ActivityCategory>>(
        future: _categoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _InlineLoading(label: '正在加载活动分类…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              onRetry: () => setState(() {
                _categoryFuture = CategoryService.load();
              }),
            );
          }
          final categories = snapshot.data ?? const <ActivityCategory>[];
          if (categories.isEmpty) {
            return const Text('暂时无法加载分类，请确认 API 已启动');
          }
          final majors = categories.where((item) => item.level == 1).toList();
          if (!majors.any((item) => item.id == _majorCategoryId)) {
            _majorCategoryId = majors.first.id;
          }
          final selectedMajor = majors.firstWhere(
            (item) => item.id == _majorCategoryId,
          );
          final leaves = categories
              .where((item) => item.parentId == _majorCategoryId)
              .toList();
          if (!leaves.any((item) => item.id == _leafCategoryId)) {
            _leafCategoryId = leaves.isEmpty
                ? null
                : selectedMajor.code == 'other'
                ? leaves
                      .where((item) => item.code == 'other_custom')
                      .firstOrNull
                      ?.id
                : leaves.first.id;
          }
          final selected = leaves.where((item) => item.id == _leafCategoryId);
          _otherSelected =
              selected.isNotEmpty && selected.first.requiresCustomLabel;
          if (selected.isNotEmpty) {
            _category = _otherSelected
                ? _customSubcategory.text.trim()
                : selected.first.name;
          }
          final featured = majors
              .where((item) => item.isFeatured && item.code != 'other')
              .take(6)
              .toList();
          final defaultMajors = featured.isEmpty
              ? majors.where((item) => item.code != 'other').take(6).toList()
              : featured;
          final extras = majors
              .where(
                (item) =>
                    item.code != 'other' &&
                    !defaultMajors.any((shown) => shown.id == item.id),
              )
              .toList();
          final other = majors.where((item) => item.code == 'other').toList();
          final visibleMajors = [
            ...defaultMajors,
            ...other,
            ...extras.where(
              (item) => _showMoreCategories || item.id == _majorCategoryId,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final columns = constraints.maxWidth >= 600 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: visibleMajors.map((major) {
                      final isSelected = major.id == _majorCategoryId;
                      return SizedBox(
                        width: width,
                        child: Semantics(
                          button: true,
                          selected: isSelected,
                          child: Material(
                            color: isSelected ? _mint : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isSelected
                                    ? _green
                                    : const Color(0xFFE7E5DF),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: InkWell(
                              key: ValueKey('major-category-${major.id}'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                _customSubcategory.clear();
                                setState(() {
                                  _selectionEdited = true;
                                  _majorCategoryId = major.id;
                                  _leafCategoryId = null;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(major.icon),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        major.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected ? _green : _ink,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 10),
              if (extras.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(
                    () => _showMoreCategories = !_showMoreCategories,
                  ),
                  icon: Icon(
                    _showMoreCategories ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    context.tr(
                      _showMoreCategories
                          ? 'showFewerCategories'
                          : 'showMoreCategories',
                    ),
                  ),
                ),
              if (selectedMajor.code != 'other')
                _CategoryDropdown(
                  key: ValueKey('leaf-category-$_majorCategoryId'),
                  label: '小分类',
                  value: _leafCategoryId,
                  items: leaves,
                  onChanged: (value) => setState(() {
                    _selectionEdited = true;
                    _leafCategoryId = value;
                    _customSubcategory.clear();
                  }),
                ),
              if (selectedMajor.code == 'other') const FieldLabel('小分类'),
              if (_otherSelected)
                TextField(
                  key: const ValueKey('custom-subcategory'),
                  controller: _customSubcategory,
                  maxLength: 15,
                  decoration: InputDecoration(
                    hintText: context.tr('customSubcategoryHint'),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      const FieldLabel('活动介绍'),
      TextField(
        controller: _description,
        maxLines: 5,
        decoration: const InputDecoration(hintText: '活动内容、适合谁，以及参加者需要准备什么…'),
      ),
    ],
  );

  Widget _schedule() => Column(
    key: const ValueKey(1),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '时间与集合点',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('公开页面只展示区域，通过审核后再显示详细地点'),
      const SizedBox(height: 24),
      const FieldLabel('开始时间'),
      TextFormField(
        key: ValueKey('start-${_startsAt?.millisecondsSinceEpoch}'),
        initialValue: _startsAt == null ? null : _formatDateTime(_startsAt!),
        readOnly: true,
        onTap: () => _pickDateTime(isStart: true),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.calendar_today),
          hintText: _startsAt == null ? '请选择开始日期和时间' : null,
          suffixIcon: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 18),
      const FieldLabel('结束时间'),
      TextFormField(
        key: ValueKey('end-${_endsAt?.millisecondsSinceEpoch}'),
        initialValue: _endsAt == null ? null : _formatDateTime(_endsAt!),
        readOnly: true,
        onTap: () => _pickDateTime(isStart: false),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.schedule),
          hintText: _endsAt == null ? '请选择结束日期和时间' : null,
          suffixIcon: const Icon(Icons.chevron_right),
        ),
      ),
      const SizedBox(height: 18),
      FutureBuilder<List<AdministrativeRegion>>(
        future: _regionFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _InlineLoading(label: '正在加载地区…');
          }
          if (snapshot.hasError) {
            return LoadFailure(
              onRetry: () => setState(() {
                _regionFuture = RegionService.load();
              }),
            );
          }
          final regions = snapshot.data ?? const <AdministrativeRegion>[];
          final cities = regions.where((region) => region.level == 1).toList();
          if (cities.isEmpty) return const Text('暂无可选择的地区');
          if (!cities.any((region) => region.code == _cityCode)) {
            _cityCode = cities.first.code;
          }
          final districts = regions
              .where((region) => region.parentCode == _cityCode)
              .toList();
          if (!districts.any((region) => region.code == _districtCode)) {
            _districtCode = districts.isEmpty ? null : districts.first.code;
          }
          _city = cities
              .firstWhere((region) => region.code == _cityCode)
              .nameZhCn;
          if (_districtCode != null) {
            _district = districts
                .firstWhere((region) => region.code == _districtCode)
                .nameZhCn;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('城市'),
              DropdownButtonFormField<String>(
                initialValue: _cityCode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.location_city),
                ),
                items: cities
                    .map(
                      (city) => DropdownMenuItem(
                        value: city.code,
                        child: Text(city.nameZhCn),
                      ),
                    )
                    .toList(),
                onChanged: (code) => setState(() {
                  _selectionEdited = true;
                  _cityCode = code;
                  _districtCode = null;
                }),
              ),
              const SizedBox(height: 18),
              const FieldLabel('所在区域'),
              DropdownButtonFormField<String>(
                key: ValueKey(_cityCode),
                initialValue: _districtCode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                items: districts
                    .map(
                      (district) => DropdownMenuItem(
                        value: district.code,
                        child: Text(district.nameZhCn),
                      ),
                    )
                    .toList(),
                onChanged: (code) => setState(() {
                  _selectionEdited = true;
                  _districtCode = code;
                }),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 18),
      const FieldLabel('准确集合点'),
      TextField(
        controller: _meetingPoint,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.pin_drop_outlined),
          hintText: '报名通过后可见',
        ),
      ),
      const SizedBox(height: 18),
      const _InfoBox(text: '为保护隐私，未加入活动的用户只能看到大致区域。'),
    ],
  );

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart
        ? (_startsAt ?? now.add(const Duration(days: 1)))
        : (_endsAt ??
              _startsAt?.add(const Duration(hours: 2)) ??
              now.add(const Duration(days: 1, hours: 2)));
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _startsAt = selected;
        if (_endsAt == null || !_endsAt!.isAfter(selected)) {
          _endsAt = selected.add(const Duration(hours: 2));
        }
      } else {
        _endsAt = selected;
      }
    });
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}  ${two(value.hour)}:${two(value.minute)}';
  }

  Widget _rules() => Column(
    key: const ValueKey(2),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '名额与参加方式',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('你可以在组织者面板审核成员并群发提醒'),
      const SizedBox(height: 25),
      const FieldLabel('预计人均费用'),
      TextField(
        controller: _price,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          prefixText: '₩ ',
          hintText: '0',
          helperText: '填写参与者预计需要自行承担的线下花销；0 表示免费',
        ),
      ),
      const SizedBox(height: 10),
      const _InfoBox(text: '平台不收取活动费用，也不提供支付或转账担保。请勿提前向陌生人转账。'),
      const SizedBox(height: 20),
      const FieldLabel('人数上限'),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text(
                '最多参加人数',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: _capacity > 2
                    ? () => setState(() => _capacity--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_capacity',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _capacity++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      ApprovalModeSelector(
        value: _approval,
        onChanged: (value) => setState(() => _approval = value),
      ),
      const SizedBox(height: 18),
      const _InfoBox(text: '发布即代表同意社区规范。禁止商业导流、歧视、危险或违法活动。'),
    ],
  );

  Future<void> _next() async {
    if (_step == 0 && _title.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写活动名称')));
      return;
    }
    if (_step == 0 && _leafCategoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择大分类和小分类')));
      return;
    }
    if (_step == 0 &&
        _otherSelected &&
        _customSubcategory.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('customSubcategoryRequired'))),
      );
      return;
    }
    if (_step == 1 && (_startsAt == null || _endsAt == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择活动的开始时间和结束时间')));
      return;
    }
    if (_step == 1 && !_endsAt!.isAfter(_startsAt!)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    if (_step == 1 && (_cityCode == null || _districtCode == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择城市和所在区域')));
      return;
    }
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    final priceAmount = int.tryParse(_price.text.trim());
    if (priceAmount == null || priceAmount < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的预计人均费用')));
      return;
    }
    setState(() => _publishing = true);
    String? uploadedCoverId;
    String? uploadedCoverUrl;
    String? token;
    try {
      token = AuthScope.of(context).token;
      if (token == null) throw Exception('登录已失效，请重新登录');
      if (_coverBytes != null) {
        final upload = await EventService.uploadCover(token, _coverBytes!);
        uploadedCoverId = upload.id;
        uploadedCoverUrl = upload.url;
      }
      await EventService.create(
        token: token,
        categoryId: _leafCategoryId!,
        coverMediaId: uploadedCoverId,
        customSubcategory: _otherSelected
            ? _customSubcategory.text.trim()
            : null,
        title: _title.text.trim(),
        description: _description.text.trim().isEmpty
            ? '一起度过轻松愉快的时间，欢迎第一次参加的新朋友。'
            : _description.text.trim(),
        cityCode: _cityCode!,
        districtCode: _districtCode!,
        startsAt: _startsAt!,
        endsAt: _endsAt!,
        capacity: _capacity,
        priceAmount: priceAmount,
        approvalRequired: _approval,
        meetingPoint: _meetingPoint.text,
      );
    } catch (error) {
      if (uploadedCoverId != null && token != null) {
        try {
          await EventService.deleteCover(token, uploadedCoverId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _publishing = false);
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    _allowLeave = true;
    widget.onCreated(
      EventItem(
        id: DateTime.now().millisecondsSinceEpoch,
        emoji: '✨',
        coverUrl: uploadedCoverUrl,
        title: _title.text.trim(),
        category: _otherSelected ? _customSubcategory.text.trim() : _category,
        time: _formatDateTime(_startsAt!),
        area: '$_city · $_district',
        distance: '你发布的',
        host: AuthScope.of(context).user?.nickname ?? '我',
        hostScore: 4.8,
        joined: 1,
        capacity: _capacity,
        price: priceAmount == 0 ? '免费' : '预计 ₩$priceAmount/人',
        approval: _approval,
        isOwned: true,
        startsAt: _startsAt,
        endsAt: _endsAt,
        beginnerFriendly:
            _title.text.contains('新手') || _description.text.contains('新手'),
        description: _description.text.trim().isEmpty
            ? '一起度过轻松愉快的时间，欢迎第一次参加的新朋友。'
            : _description.text.trim(),
        tags: [_category, _approval ? '需审核' : '直接加入'],
      ),
    );
    _title.clear();
    _description.clear();
    _meetingPoint.clear();
    _price.text = '0';
    setState(() {
      _publishing = false;
      _step = 0;
      _startsAt = null;
      _endsAt = null;
      _selectionEdited = false;
    });
  }
}

class _ButtonProgress extends StatelessWidget {
  const _ButtonProgress({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(
        width: 17,
        height: 17,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      ),
      const SizedBox(width: 9),
      Text(label),
    ],
  );
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 9),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    ),
  );
}

class LoadFailure extends StatelessWidget {
  const LoadFailure({required this.onRetry, super.key});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 180;
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 32,
            vertical: compact ? 8 : 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 48 : 88,
                height: compact ? 48 : 88,
                decoration: BoxDecoration(
                  color: _mint,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: compact ? 24 : 42,
                  color: _green,
                ),
              ),
              SizedBox(height: compact ? 8 : 22),
              if (!compact)
                Text(
                  context.tr('loadErrorTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (!compact) const SizedBox(height: 8),
              if (!compact)
                Text(
                  context.tr('loadErrorMessage'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                ),
              SizedBox(height: compact ? 8 : 22),
              if (compact)
                IconButton(
                  onPressed: onRetry,
                  tooltip: context.tr('retry'),
                  icon: const Icon(Icons.refresh_rounded),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.tr('retry')),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ApprovalModeSelector extends StatelessWidget {
  const ApprovalModeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('是否需要审核', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            value ? '申请者需经你确认后才能加入活动' : '申请后立即加入活动，无需组织者确认',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              key: const ValueKey('approval-mode-selector'),
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.fact_check_outlined),
                  label: Text('需要审核'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.flash_on_outlined),
                  label: Text('无需审核'),
                ),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    ),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String? value;
  final List<ActivityCategory> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: items
        .map(
          (item) => DropdownMenuItem(
            value: item.id,
            child: Text('${item.icon} ${item.name}'),
          ),
        )
        .toList(),
    onChanged: items.isEmpty ? null : onChanged,
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _mint,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: _green),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({required this.onUnreadChanged, super.key});
  final Future<void> Function() onUnreadChanged;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int _segment = 0;
  bool _loading = true;
  bool _readingAll = false;
  String? _error;
  List<ConversationItem> _conversations = const [];
  List<NotificationItem> _notifications = const [];
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  StreamSubscription<void>? _pushSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = RealtimeService.instance.events.listen((event) {
      if (event.type == 'message.created' ||
          event.type == 'notification.created' ||
          event.type == 'conversation.removed' ||
          event.type == 'notification.removed' ||
          event.type == 'unread.changed') {
        _scheduleRealtimeRefresh();
      }
    });
    _pushSubscription = PushNotificationService.instance.events.listen((_) {
      _scheduleRealtimeRefresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtimeSubscription?.cancel();
    _pushSubscription?.cancel();
    super.dispose();
  }

  void _scheduleRealtimeRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(milliseconds: 150),
      () => _load(showProgress: false),
    );
  }

  Future<void> _load({bool showProgress = true}) async {
    final auth = AuthScope.of(context);
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted && showProgress) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        SocialService.conversations(token),
        SocialService.notifications(token),
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = results[0] as List<ConversationItem>;
        _notifications = results[1] as List<NotificationItem>;
        _loading = false;
      });
      await widget.onUnreadChanged();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _readAll() async {
    final token = AuthScope.of(context).token;
    if (token == null || _readingAll) return;
    setState(() => _readingAll = true);
    try {
      await SocialService.readAll(token);
      await _load();
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    } finally {
      if (mounted) setState(() => _readingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      PagePadding(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('messagesTitle'),
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                TextButton(
                  onPressed: _readingAll ? null : _readAll,
                  child: Text(
                    _readingAll
                        ? context.tr('markingRead')
                        : context.tr('markAllRead'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              expandedInsets: EdgeInsets.zero,
              segments: [
                ButtonSegment(
                  value: 0,
                  label: _segmentLabel(
                    context.tr('eventChats'),
                    _chatUnread('event'),
                  ),
                ),
                ButtonSegment(
                  value: 1,
                  label: _segmentLabel(
                    context.tr('directMessages'),
                    _chatUnread('direct'),
                  ),
                ),
                ButtonSegment(
                  value: 2,
                  label: _segmentLabel(
                    context.tr('notifications'),
                    _notifications.where((item) => !item.read).length,
                  ),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ],
        ),
      ),
      Expanded(child: _content()),
    ],
  );

  int _chatUnread(String type) => _conversations
      .where((item) => item.type == type)
      .fold(0, (total, item) => total + item.unreadCount);

  Widget _segmentLabel(String label, int unread) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label),
      if (unread > 0) ...[
        const SizedBox(width: 5),
        Badge(label: Text('$unread')),
      ],
    ],
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(context.tr('reloadMessages')),
        ),
      );
    }
    if (_segment == 2) return _notices();
    final type = _segment == 0 ? 'event' : 'direct';
    final items = _conversations.where((item) => item.type == type).toList();
    if (items.isEmpty) {
      return Center(child: Text(context.tr('noConversations')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: items
            .map(
              (item) => Slidable(
                key: ValueKey('conversation-${item.id}'),
                startActionPane: ActionPane(
                  motion: const StretchMotion(),
                  extentRatio: .26,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _markConversationRead(item),
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      icon: Icons.done_all,
                      label: '已读',
                    ),
                  ],
                ),
                endActionPane: ActionPane(
                  motion: const StretchMotion(),
                  extentRatio: .3,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _removeConversation(item),
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_outline,
                      label: item.type == 'event' ? '退出群聊' : '删除',
                    ),
                  ],
                ),
                child: _ChatTile(
                  emoji: item.type == 'event' ? '👥' : '💬',
                  title: item.title,
                  message: item.lastMessageType == 'event_cancelled'
                      ? '${context.tr('eventCancelled')} · ${context.tr('cancellationReason')}：${item.lastMessageBody ?? ''}'
                      : item.lastMessageBody ?? context.tr('chatCreated'),
                  time: _relativeTime(item.lastMessageAt),
                  unread: item.unreadCount,
                  onTap: () => _openChat(item),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _notices() {
    if (_notifications.isEmpty) {
      return Center(child: Text(context.tr('noNotifications')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _notifications
            .map(
              (item) => Slidable(
                key: ValueKey('notification-${item.id}'),
                startActionPane: ActionPane(
                  motion: const StretchMotion(),
                  extentRatio: .26,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _readNotification(item),
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      icon: Icons.done_all,
                      label: '已读',
                    ),
                  ],
                ),
                endActionPane: ActionPane(
                  motion: const StretchMotion(),
                  extentRatio: .26,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _deleteNotification(item),
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_outline,
                      label: '删除',
                    ),
                  ],
                ),
                child: _NoticeTile(
                  icon: _notificationIcon(item.type),
                  title: item.title,
                  subtitle: item.body,
                  time: _relativeTime(item.createdAt),
                  unread: !item.read,
                  onTap: () => _openNotification(item),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _readNotification(NotificationItem item) async {
    if (item.read) return;
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      await SocialService.readNotification(token, item.id);
      await _load();
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  Future<void> _openNotification(NotificationItem item) async {
    final token = AuthScope.of(context).token;
    if (token != null && !item.read) {
      try {
        await SocialService.readNotification(token, item.id);
      } catch (error) {
        if (mounted) _showMessageError(context, '$error');
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationDetailPage(item: item)),
    );
    await _load(showProgress: false);
  }

  Future<void> _markConversationRead(ConversationItem item) async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      await SocialService.readConversationLatest(token, item.id);
      await _load(showProgress: false);
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  Future<void> _removeConversation(ConversationItem item) async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      await SocialService.removeConversation(token, item.id);
      if (!mounted) return;
      setState(
        () => _conversations = _conversations
            .where((conversation) => conversation.id != item.id)
            .toList(),
      );
      await widget.onUnreadChanged();
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  Future<void> _deleteNotification(NotificationItem item) async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      await SocialService.deleteNotification(token, item.id);
      if (!mounted) return;
      setState(
        () => _notifications = _notifications
            .where((notification) => notification.id != item.id)
            .toList(),
      );
      await widget.onUnreadChanged();
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  Future<void> _openChat(ConversationItem item) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatPage(conversation: item)));
    await _load();
  }
}

String _relativeTime(DateTime? value) {
  if (value == null) return '';
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes}分钟前';
  if (difference.inDays < 1) return '${difference.inHours}小时前';
  if (difference.inDays < 7) return '${difference.inDays}天前';
  return '${value.month}/${value.day}';
}

IconData _notificationIcon(String type) {
  if (type == 'announcement') return Icons.campaign_outlined;
  if (type == 'new_message') return Icons.chat_bubble_outline;
  if (type.contains('approved')) return Icons.check_circle_outline;
  if (type.contains('rejected')) return Icons.cancel_outlined;
  if (type.contains('application')) return Icons.person_add_alt_1;
  return Icons.notifications_outlined;
}

class NotificationDetailPage extends StatelessWidget {
  const NotificationDetailPage({required this.item, super.key});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知详情'), actions: const [_HomeAction()]),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: _mint,
          child: Icon(_notificationIcon(item.type), color: _green, size: 30),
        ),
        const SizedBox(height: 20),
        Text(
          item.title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _notificationTime(item.createdAt),
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Text(item.body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

String _notificationTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.emoji,
    required this.title,
    required this.message,
    required this.time,
    required this.onTap,
    this.unread = 0,
  });
  final String emoji;
  final String title;
  final String message;
  final String time;
  final VoidCallback onTap;
  final int unread;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      onTap: onTap,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: _mint,
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            time,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 5),
          if (unread > 0) Badge(label: Text('$unread')),
        ],
      ),
    ),
  );
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.onTap,
    this.unread = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final VoidCallback onTap;
  final bool unread;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    tileColor: unread ? _mint.withValues(alpha: .55) : null,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    contentPadding: const EdgeInsets.symmetric(vertical: 5),
    leading: CircleAvatar(
      backgroundColor: _mint,
      child: Icon(icon, color: _green),
    ),
    title: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (unread) const Badge(),
      ],
    ),
    subtitle: Text(subtitle),
    trailing: Text(
      time,
      style: const TextStyle(fontSize: 12, color: Colors.black45),
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({required this.conversation, super.key});
  final ConversationItem conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  bool _loading = true;
  bool _sending = false;
  bool _loadingOlder = false;
  String? _error;
  String? _nextCursor;
  bool _hasMore = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  List<ChatMessage> _messages = const [];
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = RealtimeService.instance.events.listen((event) {
      if ((event.type == 'message.created' ||
              event.type == 'message.updated') &&
          event.data['conversationId']?.toString() == widget.conversation.id) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer(
          const Duration(milliseconds: 100),
          () => _load(showProgress: false),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _realtimeSubscription?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool showProgress = true}) async {
    final auth = AuthScope.of(context);
    final token = auth.token;
    final userId = auth.user?.id;
    if (token == null || userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (showProgress && mounted) {
      final cached = await SocialService.cachedMessages(
        userId,
        widget.conversation.id,
      );
      final pending = await SocialService.pendingMessages(
        userId,
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = [...cached, ...pending];
        _loading = cached.isEmpty && pending.isEmpty;
        _error = null;
      });
    }
    try {
      final page = await SocialService.messages(token, widget.conversation.id);
      final pending = await SocialService.pendingMessages(
        userId,
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _messages = [...page.items, ...pending];
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
      await SocialService.cacheMessages(
        userId,
        widget.conversation.id,
        page.items,
      );
      for (final message in pending) {
        unawaited(_deliverPending(message));
      }
      if (page.items.isNotEmpty) {
        await SocialService.readConversation(
          token,
          widget.conversation.id,
          page.items.last.id,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messages.isEmpty ? '$error' : null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.conversation.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          Text(
            widget.conversation.type == 'event'
                ? context
                      .tr('eventChatMembers')
                      .replaceFirst(
                        '{count}',
                        '${widget.conversation.memberCount}',
                      )
                : context.tr('privateChat'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [const _HomeAction()],
    ),
    body: Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: FilledButton(
                    onPressed: _load,
                    child: Text(context.tr('reload')),
                  ),
                )
              : _messages.isEmpty
              ? Center(child: Text(context.tr('emptyChat')))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                  itemCount: _messages.length + (_hasMore ? 1 : 0),
                  itemBuilder: (_, index) {
                    if (_hasMore && index == 0) {
                      return Center(
                        child: TextButton.icon(
                          onPressed: _loadingOlder ? null : _loadOlder,
                          icon: _loadingOlder
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.history),
                          label: Text(context.tr('loadOlderMessages')),
                        ),
                      );
                    }
                    final messageIndex = index - (_hasMore ? 1 : 0);
                    final message = _messages[messageIndex];
                    if (message.messageType == 'event_cancelled') {
                      return EventCancellationNotice(reason: message.body);
                    }
                    return _Bubble(
                      text: message.recalledAt == null
                          ? message.body
                          : context.tr('messageRecalled'),
                      mine:
                          message.senderUserId ==
                          AuthScope.of(context).user?.id,
                      sender: message.senderName,
                      pending: message.pending,
                      failed: message.failed,
                      recalled: message.recalledAt != null,
                      mediaUrl: message.mediaThumbnailUrl ?? message.mediaUrl,
                      mediaPreviewUrl: message.mediaUrl,
                      replyText: message.replyToMessageId == null
                          ? null
                          : (message.replyToBody ??
                                context.tr('messageRecalled')),
                      onLongPress: message.pending
                          ? () => _deliverPending(message)
                          : () => _showMessageActions(message),
                    );
                  },
                ),
        ),
        if (_replyingTo != null || _editingMessage != null)
          Material(
            color: _mint,
            child: ListTile(
              dense: true,
              leading: Icon(_editingMessage == null ? Icons.reply : Icons.edit),
              title: Text(
                context.tr(
                  _editingMessage == null
                      ? 'replyingToMessage'
                      : 'editingMessage',
                ),
              ),
              subtitle: Text(
                (_editingMessage ?? _replyingTo)!.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => setState(() {
                  _replyingTo = null;
                  _editingMessage = null;
                  _input.clear();
                }),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        if (widget.conversation.status != 'active')
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.tr('conversationReadOnly')),
          )
        else
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _chooseChatImageSource,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: InputDecoration(
                        hintText: context.tr('sendMessage'),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _send() async {
    final body = _input.text.trim();
    final token = AuthScope.of(context).token;
    if (body.isEmpty || token == null || _sending) return;
    if (_editingMessage != null) {
      final editing = _editingMessage!;
      setState(() => _sending = true);
      try {
        final edited = await SocialService.editMessage(
          token,
          widget.conversation.id,
          editing.id,
          body,
        );
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((item) => item.id == edited.id ? edited : item)
              .toList();
          _editingMessage = null;
          _input.clear();
        });
      } catch (error) {
        if (mounted) _showMessageError(context, '$error');
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }
    final clientId = SocialService.newClientMessageId();
    final pending = ChatMessage(
      id: clientId,
      senderUserId: AuthScope.of(context).user?.id,
      body: body,
      createdAt: DateTime.now(),
      clientMessageId: clientId,
      replyToMessageId: _replyingTo?.id,
      replyToBody: _replyingTo?.body,
      pending: true,
    );
    final userId = AuthScope.of(context).user!.id;
    setState(() => _sending = true);
    try {
      await SocialService.savePending(userId, widget.conversation.id, pending);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, pending];
        _input.clear();
        _replyingTo = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _sending = false);
        _showMessageError(context, '$error');
      }
      return;
    }
    await _deliverPending(pending);
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _chooseChatImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.tr('takePhoto')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(context.tr('chooseFromGallery')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null && mounted) await _pickChatImage(source);
  }

  Future<void> _pickChatImage(ImageSource source) async {
    final token = AuthScope.of(context).token;
    if (token == null || _sending) return;
    final tooLargeMessage = context.tr('chatImageTooLarge');
    final processFailedMessage = context.tr('chatImageProcessFailed');
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
    } catch (_) {
      if (mounted) _showMessageError(context, processFailedMessage);
      return;
    }
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    String? uploadedMediaId;
    try {
      final originalBytes = await picked.readAsBytes();
      final bytes = await compressChatImage(originalBytes);
      if (bytes.length > chatImageTargetBytes) {
        throw Exception(tooLargeMessage);
      }
      final uploaded = await SocialService.uploadChatImage(
        token,
        widget.conversation.id,
        bytes,
        'chat-${DateTime.now().millisecondsSinceEpoch}.jpg',
        'image/jpeg',
      );
      uploadedMediaId = uploaded['mediaAssetId'];
      await SocialService.sendMessage(
        token,
        widget.conversation.id,
        '',
        SocialService.newClientMessageId(),
        mediaAssetId: uploadedMediaId,
      );
      uploadedMediaId = null;
      await _load(showProgress: false);
    } on FormatException {
      if (mounted) _showMessageError(context, processFailedMessage);
    } catch (error) {
      if (uploadedMediaId != null) {
        try {
          await SocialService.deleteChatMedia(
            token,
            widget.conversation.id,
            uploadedMediaId,
          );
        } catch (_) {
          // The media remains unreferenced and can be removed by maintenance.
        }
      }
      if (mounted) _showMessageError(context, '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deliverPending(ChatMessage pending) async {
    final auth = AuthScope.of(context);
    final token = auth.token;
    final userId = auth.user?.id;
    final clientId = pending.clientMessageId;
    if (token == null || userId == null || clientId == null) return;
    try {
      final message = await SocialService.sendMessage(
        token,
        widget.conversation.id,
        pending.body,
        clientId,
        replyToMessageId: pending.replyToMessageId,
      );
      await SocialService.removePending(
        userId,
        widget.conversation.id,
        clientId,
      );
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages.where(
            (item) => item.clientMessageId != clientId && item.id != message.id,
          ),
          message,
        ];
      });
      await SocialService.cacheMessages(
        userId,
        widget.conversation.id,
        _messages.where((item) => !item.pending).toList(),
      );
      await SocialService.readConversation(
        token,
        widget.conversation.id,
        message.id,
      );
      unawaited(_load(showProgress: false));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map(
              (item) => item.clientMessageId == clientId
                  ? item.copyWith(pending: true, failed: true)
                  : item,
            )
            .toList();
      });
      _showMessageError(context, context.tr('messageQueuedForRetry'));
    }
  }

  Future<void> _loadOlder() async {
    final token = AuthScope.of(context).token;
    if (token == null || _nextCursor == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await SocialService.messages(
        token,
        widget.conversation.id,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        final existing = _messages.map((item) => item.id).toSet();
        _messages = [
          ...page.items.where((item) => !existing.contains(item.id)),
          ..._messages,
        ];
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
      await SocialService.cacheMessages(
        AuthScope.of(context).user!.id,
        widget.conversation.id,
        _messages.where((item) => !item.pending).toList(),
      );
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    if (message.recalledAt != null) return;
    final mine = message.senderUserId == AuthScope.of(context).user?.id;
    final canRecall =
        mine &&
        DateTime.now().difference(message.createdAt) <=
            const Duration(minutes: 5);
    final canEdit =
        mine &&
        DateTime.now().difference(message.createdAt) <=
            const Duration(minutes: 15);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(context.tr('replyMessage')),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _replyingTo = message;
                  _editingMessage = null;
                  _input.clear();
                });
              },
            ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(context.tr('recallMessage')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _recall(message);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.tr('editMessage')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _editingMessage = message;
                    _replyingTo = null;
                    _input.text = message.body;
                    _input.selection = TextSelection.collapsed(
                      offset: _input.text.length,
                    );
                  });
                },
              ),
            if (!mine)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(context.tr('reportMessage')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _report(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _recall(ChatMessage message) async {
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      final recalled = await SocialService.recallMessage(
        token,
        widget.conversation.id,
        message.id,
      );
      if (mounted) {
        setState(
          () => _messages = _messages
              .map((item) => item.id == message.id ? recalled : item)
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }

  Future<void> _report(ChatMessage message) async {
    const categories = [
      'harassment',
      'inappropriate_content',
      'spam',
      'fraud',
      'privacy_violation',
      'unsafe_behavior',
    ];
    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('chooseMessageReportReason')),
        children: categories
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, value),
                child: Text(context.tr('messageReport_$value')),
              ),
            )
            .toList(),
      ),
    );
    if (category == null || !mounted) return;
    final descriptionController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('reportMessage')),
        content: TextField(
          controller: descriptionController,
          maxLength: 1000,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: context.tr('reportDescription'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('eventCoverCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('submitFeedback')),
          ),
        ],
      ),
    );
    final description = descriptionController.text.trim();
    descriptionController.dispose();
    if (confirmed != true || !mounted) return;
    final token = AuthScope.of(context).token;
    if (token == null) return;
    try {
      await SocialService.reportMessage(
        token,
        widget.conversation.id,
        message.id,
        category,
        description.isEmpty ? null : description,
      );
      if (mounted) {
        _showMessageError(context, context.tr('messageReportSubmitted'));
      }
    } catch (error) {
      if (mounted) _showMessageError(context, '$error');
    }
  }
}

void _showMessageError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.mine,
    this.sender,
    this.pending = false,
    this.failed = false,
    this.recalled = false,
    this.mediaUrl,
    this.mediaPreviewUrl,
    this.replyText,
    this.onLongPress,
  });
  final String text;
  final bool mine;
  final String? sender;
  final bool pending;
  final bool failed;
  final bool recalled;
  final String? mediaUrl;
  final String? mediaPreviewUrl;
  final String? replyText;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!mine && sender != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              sender!,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? _green : Colors.white,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: mine ? const Radius.circular(4) : null,
                bottomLeft: mine ? null : const Radius.circular(4),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (replyText != null)
                  Container(
                    width: 220,
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: mine ? Colors.white12 : _cream,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      replyText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: mine ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                if (mediaUrl != null)
                  GestureDetector(
                    key: ValueKey('chat-image-${mediaPreviewUrl ?? mediaUrl}'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatImagePreviewPage(
                          imageUrl: mediaPreviewUrl ?? mediaUrl!,
                        ),
                      ),
                    ),
                    child: Hero(
                      tag: 'chat-image-${mediaPreviewUrl ?? mediaUrl}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          mediaUrl!,
                          width: 220,
                          height: 165,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 220,
                            height: 80,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (text.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: mediaUrl == null ? 0 : 8),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: mine ? Colors.white : _ink,
                        fontStyle: recalled ? FontStyle.italic : null,
                      ),
                    ),
                  ),
                if (pending)
                  Icon(
                    failed ? Icons.error_outline : Icons.schedule,
                    size: 14,
                    color: mine ? Colors.white70 : Colors.black45,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class ChatImagePreviewPage extends StatelessWidget {
  const ChatImagePreviewPage({
    required this.imageUrl,
    this.titleKey = 'chatImagePreview',
    this.heroTag,
    super.key,
  });

  final String imageUrl;
  final String titleKey;
  final String? heroTag;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(context.tr(titleKey)),
    ),
    body: SafeArea(
      child: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Center(
            child: Hero(
              tag: heroTag ?? 'chat-image-$imageUrl',
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final user = auth.user!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        Row(
          children: [
            Text(
              context.tr('profile'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const _ProfileInfoPage(
                    title: '设置',
                    message: '账号、通知、隐私和语言设置可以在这里统一管理。',
                  ),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        UserAvatar(user: user),
                        Positioned(
                          right: -5,
                          bottom: -5,
                          child: Material(
                            color: _green,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => showAvatarEditor(context),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.camera_alt,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.nickname,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(user.email),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => showAvatarEditor(context),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat(value: '4.8', label: context.tr('trust')),
                    _Stat(value: '12', label: context.tr('joined')),
                    _Stat(value: '3', label: context.tr('organized')),
                    _Stat(value: '96%', label: context.tr('attendance')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: _ink,
          child: InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SafetyCenterPage())),
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF365345),
                    child: Icon(Icons.shield_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('safetyCenter'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          context.tr('safetySubtitle'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          context.tr('activitiesCommunity'),
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              _Menu(
                icon: Icons.event_available_outlined,
                title: context.tr('myEvents'),
                subtitle: '查看我发布和参加的活动',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MyActivitiesPage(token: auth.token!),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 58),
              _Menu(
                icon: Icons.star_outline,
                title: context.tr('trustReviews'),
                subtitle: '守时 · 友善 · 沟通顺畅',
                onTap: () => _openInfo(
                  context,
                  context.tr('trustReviews'),
                  '参加活动并完成签到后，双方可以提交信誉评价。评价记录接口将在活动闭环的评价阶段接入。',
                ),
              ),
              const Divider(height: 1, indent: 58),
              _Menu(
                icon: Icons.block_outlined,
                title: context.tr('blocksReports'),
                onTap: () => _openInfo(
                  context,
                  context.tr('blocksReports'),
                  '你可以在活动详情或用户资料中屏蔽用户、提交举报，并在这里查看处理进度。',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              _Menu(
                icon: Icons.help_outline,
                title: context.tr('helpRules'),
                onTap: () => _openInfo(
                  context,
                  context.tr('helpRules'),
                  '参加线下活动前请确认时间、地点和费用，不要向陌生人提前转账；遇到危险请立即联系当地警方。',
                ),
              ),
              const Divider(height: 1, indent: 58),
              _Menu(
                icon: Icons.privacy_tip_outlined,
                title: context.tr('privacyAccount'),
                subtitle: context.tr('privacySubtitle'),
                onTap: () => _openInfo(
                  context,
                  context.tr('privacyAccount'),
                  '准确集合点仅对组织者和报名成功的参与者开放。账号注销和隐私数据管理将在此页面提供。',
                ),
              ),
              const Divider(height: 1, indent: 58),
              _Menu(
                icon: Icons.language,
                title: context.tr('language'),
                subtitle:
                    languageLabels[Localizations.localeOf(
                      context,
                    ).languageCode],
                onTap: () => _showLanguagePicker(context),
              ),
              const Divider(height: 1, indent: 58),
              _Menu(
                icon: Icons.logout,
                title: context.tr('logout'),
                onTap: auth.logout,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openInfo(BuildContext context, String title, String message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProfileInfoPage(title: title, message: message),
      ),
    );
  }
}

Future<void> _openSimilarEvent(BuildContext context, String eventId) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) => Scaffold(
        appBar: AppBar(
          title: Text(routeContext.tr('publishSimilar')),
          actions: const [_HomeAction()],
        ),
        body: CreateEventPage(
          sourceEventId: eventId,
          onCreated: (_) {
            Navigator.of(routeContext).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(context.tr('eventCreated'))));
          },
        ),
      ),
    ),
  );
}

class MyActivitiesPage extends StatefulWidget {
  const MyActivitiesPage({
    required this.token,
    this.selectSource = false,
    super.key,
  });
  final bool selectSource;
  final String token;

  @override
  State<MyActivitiesPage> createState() => _MyActivitiesPageState();
}

class _MyActivitiesPageState extends State<MyActivitiesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = EventService.myActivities(widget.token);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.selectSource ? context.tr('createFromPrevious') : '我的活动',
      ),
      actions: const [_HomeAction()],
      bottom: widget.selectSource
          ? null
          : TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: '我发布的'),
                Tab(text: '我参加的'),
              ],
            ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return LoadFailure(
            onRetry: () => setState(() {
              _future = EventService.myActivities(widget.token);
            }),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final organized = rows
            .where((row) => row['member_role'] == 'organizer')
            .toList();
        final joined = rows
            .where((row) => row['member_role'] != 'organizer')
            .toList();
        if (widget.selectSource) {
          return _activityList(
            organized,
            context.tr('noPreviousEvents'),
            isOrganizer: true,
          );
        }
        return TabBarView(
          controller: _tabs,
          children: [
            _activityList(organized, '你还没有发布活动', isOrganizer: true),
            _activityList(joined, '你还没有参加活动'),
          ],
        );
      },
    ),
  );

  Widget _activityList(
    List<Map<String, dynamic>> rows,
    String emptyText, {
    bool isOrganizer = false,
  }) {
    if (rows.isEmpty) return Center(child: Text(emptyText));
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _future = EventService.myActivities(widget.token);
        });
        await _future;
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final row = rows[index];
          final startsAt = DateTime.tryParse('${row['starts_at']}')?.toLocal();
          final endsAt = DateTime.tryParse('${row['ends_at']}');
          final isPast = endsAt != null && !endsAt.isAfter(DateTime.now());
          final price = (row['price_amount'] as num?)?.toInt() ?? 0;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: CircleAvatar(
                backgroundColor: _mint,
                child: Text('${row['category_icon'] ?? '✨'}'),
              ),
              title: Text(
                '${row['event_status'] == 'cancelled'
                    ? '${context.tr('eventCancelled')} · '
                    : isPast
                    ? '${context.tr('pastActivity')} · '
                    : ''}${row['title'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${row['city_name'] ?? row['city_code']} · ${row['district_name'] ?? row['district_code']}\n'
                '${_formatActivityDate(startsAt)} · ${price == 0 ? '免费' : '预计 ₩$price/人'}',
              ),
              isThreeLine: true,
              trailing: isOrganizer && !widget.selectSource
                  ? TextButton(
                      onPressed: () =>
                          _openSimilarEvent(context, '${row['id']}'),
                      child: Text(context.tr('publishSimilar')),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () async {
                if (widget.selectSource) {
                  Navigator.of(context).pop('${row['id']}');
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _MyActivityRecordPage(
                      activity: row,
                      token: widget.token,
                      isOrganizer: isOrganizer,
                    ),
                  ),
                );
                if (mounted) {
                  setState(() {
                    _future = EventService.myActivities(widget.token);
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  String _formatActivityDate(DateTime? value) {
    if (value == null) return '时间待定';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }
}

class _MyActivityRecordPage extends StatefulWidget {
  const _MyActivityRecordPage({
    required this.activity,
    required this.token,
    required this.isOrganizer,
  });
  final Map<String, dynamic> activity;
  final String token;
  final bool isOrganizer;

  @override
  State<_MyActivityRecordPage> createState() => _MyActivityRecordPageState();
}

class _MyActivityRecordPageState extends State<_MyActivityRecordPage> {
  late final Map<String, dynamic> activity = Map.of(widget.activity);
  String get token => widget.token;
  bool get isOrganizer => widget.isOrganizer;
  bool get activityEnded {
    final endsAt = DateTime.tryParse('${activity['ends_at'] ?? ''}')?.toLocal();
    return activity['event_status'] == 'completed' ||
        (endsAt != null && !endsAt.isAfter(DateTime.now()));
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CancelEventDialog(token: token, eventId: '${activity['id']}'),
    );
    if (!mounted || reason == null) return;
    setState(() {
      activity['event_status'] = 'cancelled';
      activity['cancellation_reason'] = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final price = (activity['price_amount'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(isOrganizer ? context.tr('activityManagement') : '活动记录'),
        actions: const [_HomeAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${activity['title'] ?? ''}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          _InfoBox(text: '${activity['description'] ?? '暂无活动介绍'}'),
          const SizedBox(height: 18),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('活动区域'),
            subtitle: Text(
              '${activity['city_name'] ?? activity['city_code']} · ${activity['district_name'] ?? activity['district_code']}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('预计人均费用'),
            subtitle: Text(price == 0 ? '免费' : '₩$price/人，线下自行结算'),
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('活动状态'),
            subtitle: Text(
              '${activity['event_status'] == 'cancelled' ? context.tr('eventCancelled') : activity['event_status']} · 报名状态 ${activity['membership_status']}',
            ),
          ),
          if (activity['event_status'] == 'cancelled')
            EventCancellationNotice(
              reason: '${activity['cancellation_reason'] ?? ''}',
            ),
          if (isOrganizer) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FeedbackActionCard(
                  icon: Icons.copy_outlined,
                  label: context.tr('publishSimilar'),
                  onTap: () => _openSimilarEvent(context, '${activity['id']}'),
                ),
                if (activity['event_status'] != 'cancelled' && !activityEnded)
                  FeedbackActionCard(
                    icon: Icons.event_busy_outlined,
                    label: context.tr('cancelEvent'),
                    color: Theme.of(context).colorScheme.error,
                    onTap: _cancel,
                  ),
              ],
            ),
            if (activity['event_status'] != 'cancelled' && !activityEnded) ...[
              const Divider(height: 34),
              _OrganizerApplications(
                token: token,
                eventId: '${activity['id']}',
              ),
            ],
          ] else if (activityEnded &&
              activity['event_status'] != 'cancelled') ...[
            FeedbackActionGrid(
              token: token,
              eventId: '${activity['id']}',
              targetType: 'activity',
            ),
          ],
        ],
      ),
    );
  }
}

class _OrganizerApplications extends StatefulWidget {
  const _OrganizerApplications({required this.token, required this.eventId});

  final String token;
  final String eventId;

  @override
  State<_OrganizerApplications> createState() => _OrganizerApplicationsState();
}

class _OrganizerApplicationsState extends State<_OrganizerApplications> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  final Set<String> _processing = {};

  Future<List<Map<String, dynamic>>> _load() =>
      EventService.applications(widget.token, widget.eventId);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  context.tr('applications'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: context.tr('refresh'),
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              LoadFailure(onRetry: _reload)
            else if ((snapshot.data ?? const []).isEmpty)
              _InfoBox(text: context.tr('noPendingApplications'))
            else
              ...(snapshot.data ?? const <Map<String, dynamic>>[]).map(
                _applicationCard,
              ),
          ],
        );
      },
    );
  }

  Widget _applicationCard(Map<String, dynamic> application) {
    final userId = '${application['user_id']}';
    final processing = _processing.contains(userId);
    final partySize = (application['party_size'] as num?)?.toInt() ?? 1;
    final note = '${application['application_note'] ?? ''}'.trim();
    final trustScore = application['trust_score'] ?? 0;
    final nickname = '${application['nickname'] ?? context.tr('applicant')}';
    final createdAt = DateTime.tryParse(
      '${application['created_at'] ?? ''}',
    )?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openPublicProfile(
                    context,
                    userId,
                    eventId: widget.eventId,
                  ),
                  child: UserAvatarImage(
                    nickname: nickname,
                    avatarUrl: application['avatar_url'] as String?,
                    radius: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _openPublicProfile(
                      context,
                      userId,
                      eventId: widget.eventId,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${context.tr('partySize')}: $partySize · '
                          '${context.tr('trust')}: $trustScore',
                        ),
                        Text(
                          '❤ ${application['like_count'] ?? 0}',
                          style: const TextStyle(
                            color: Colors.pink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (application['member_risk_tag'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _RiskPill(
                              text: feedbackTagLabel(
                                context,
                                '${application['member_risk_tag']}',
                              ),
                            ),
                          ),
                        if (createdAt != null)
                          Text(
                            '申请时间：${_notificationTime(createdAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${context.tr('applicationNote')}: '
              '${note.isEmpty ? '未填写' : note}',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: processing
                        ? null
                        : () => _decide(application, approve: false),
                    child: Text(context.tr('reject')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: processing
                        ? null
                        : () => _decide(application, approve: true),
                    child: processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.tr('approve')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decide(
    Map<String, dynamic> application, {
    required bool approve,
  }) async {
    final userId = '${application['user_id']}';
    String? reason;
    if (!approve) {
      reason = await _requestRejectionReason();
      if (reason == null) return;
    }
    setState(() => _processing.add(userId));
    try {
      if (approve) {
        await EventService.approveApplication(
          widget.token,
          widget.eventId,
          userId,
        );
      } else {
        await EventService.rejectApplication(
          widget.token,
          widget.eventId,
          userId,
          reason!,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('applicationUpdated'))));
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(userId));
    }
  }

  Future<String?> _requestRejectionReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('rejectionReason')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: context.tr('rejectionReasonHint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 2) Navigator.pop(dialogContext, value);
            },
            child: Text(context.tr('confirmReject')),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason;
  }
}

class _ProfileInfoPage extends StatelessWidget {
  const _ProfileInfoPage({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: const [_HomeAction()]),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: _InfoBox(text: message),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ],
  );
}

Future<void> _showLanguagePicker(BuildContext context) async {
  final current = Localizations.localeOf(context).languageCode;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                context.tr('languageTitle'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final entry in languageLabels.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == current
                    ? const Icon(Icons.check_circle, color: _green)
                    : null,
                onTap: () {
                  AppLocaleScope.of(context).onChanged(Locale(entry.key));
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: _green),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: const Icon(Icons.chevron_right),
  );
}

class SafetyCenterPage extends StatefulWidget {
  const SafetyCenterPage({super.key});

  @override
  State<SafetyCenterPage> createState() => _SafetyCenterPageState();
}

class _SafetyCenterPageState extends State<SafetyCenterPage> {
  bool _active = false;
  String _interval = '60 分钟';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('安全中心'), actions: const [_HomeAction()]),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _active ? _mint : _ink,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              Icon(
                _active ? Icons.verified_user : Icons.shield_outlined,
                size: 48,
                color: _active ? _green : Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                _active ? '安全会面进行中' : '开启安全会面',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _active ? _ink : Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _active ? '下次确认：$_interval后' : '按时确认状态，逾时提醒紧急联系人',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _active ? Colors.black54 : Colors.white70,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => setState(() => _active = !_active),
                  style: FilledButton.styleFrom(
                    backgroundColor: _active ? Colors.white : _orange,
                    foregroundColor: _active ? _ink : Colors.white,
                  ),
                  child: Text(_active ? '我现在安全 · 完成确认' : '开始设置'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FieldLabel('确认频率'),
        DropdownButtonFormField<String>(
          initialValue: _interval,
          items: [
            '30 分钟',
            '60 分钟',
            '90 分钟',
          ].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
          onChanged: (v) => setState(() => _interval = v!),
        ),
        const SizedBox(height: 22),
        const FieldLabel('紧急联系人'),
        Card(
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: _mint,
              child: Icon(Icons.person_outline, color: _green),
            ),
            title: const Text(
              '姐姐 · 138••••2048',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text('仅在授权的安全会面中使用'),
            trailing: const Icon(Icons.edit_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _Menu(
                icon: Icons.location_on_outlined,
                title: '位置分享',
                subtitle: '仅活动期间 · 精确位置',
                onTap: () {},
              ),
              const Divider(height: 1, indent: 58),
              _Menu(icon: Icons.sms_outlined, title: '紧急分享模板', onTap: () {}),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _showEmergency(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.sos),
          label: const Text('需要紧急帮助'),
        ),
        const SizedBox(height: 12),
        Text(
          '本功能不是救援服务。如面临即时危险，请拨打韩国警方 112 或消防急救 119。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    ),
  );

  void _showEmergency(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '紧急帮助',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('若你正处于危险中，请优先联系当地紧急服务。'),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.share_location_outlined),
              label: const Text('通知紧急联系人并分享位置'),
            ),
          ],
        ),
      ),
    );
  }
}
