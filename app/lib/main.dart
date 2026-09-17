import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth.dart';
import 'category_service.dart';
import 'event_service.dart';
import 'l10n.dart';
import 'build_failure.dart';
import 'location_service.dart';

void main() => runApp(const DaziApp());

const _ink = Color(0xFF17162C);
const _green = Color(0xFF5B4BDB);
const _mint = Color(0xFFEDEAFF);
const _cream = Color(0xFFF3F5FA);
const _orange = Color(0xFFFF6B57);

class DaziApp extends StatefulWidget {
  const DaziApp({super.key, this.home});
  final Widget? home;

  @override
  State<DaziApp> createState() => _DaziAppState();
}

class _DaziAppState extends State<DaziApp> {
  Locale _locale = const Locale('zh');
  Key? _recoveryKey;
  ErrorWidgetBuilder? _previousErrorBuilder;
  ErrorWidgetBuilder? _installedErrorBuilder;
  static const _isTestEnvironment = bool.fromEnvironment('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
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
        home:
            widget.home ??
            AuthGate(authenticatedBuilder: (_) => const AppShell()),
      ),
    );
  }
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
    this.price = '免费',
    this.description = '',
    this.tags = const [],
    this.approval = false,
    this.isJoined = false,
    this.isOwned = false,
    this.startsAt,
    this.endsAt,
    this.beginnerFriendly = false,
  });

  final int id;
  final String emoji;
  final String title;
  final String category;
  final String time;
  final String area;
  final String distance;
  final String host;
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
  int _unread = 3;
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

  @override
  void initState() {
    super.initState();
    _events = List<EventItem>.of(widget.initialEvents ?? const []);
    _eventsLoading = widget.loadRemoteEvents;
    if (widget.loadRemoteEvents || widget.eventLoader != null) _loadEvents();
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
      emoji: '${json['category_icon'] ?? '✨'}',
      title: '${json['title'] ?? ''}',
      category: '${json['category_name'] ?? ''}',
      time: time,
      area: [city, district].where((value) => value.isNotEmpty).join(' · '),
      distance: distanceMeters == null
          ? '距离待计算'
          : '${(distanceMeters / 1000).toStringAsFixed(1)} km',
      host: '${json['organizer_name'] ?? '活动组织者'}',
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
      _unread++;
    });
    _loadEvents();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('活动发布成功，已生成活动群聊')));
  }

  void _locationChanged(AppLocation location) {
    final changed =
        _latitude == null ||
        _longitude == null ||
        (_latitude! - location.latitude).abs() > .0001 ||
        (_longitude! - location.longitude).abs() > .0001;
    if (!changed) return;
    _latitude = location.latitude;
    _longitude = location.longitude;
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
        onCreated: _created,
        loadRemoteData: widget.loadRemoteEvents,
      ),
      MessagesPage(onReadAll: () => setState(() => _unread = 0)),
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
        onSelected: (value) => setState(() => _index = value),
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
  String? _locationLanguage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = Localizations.localeOf(context).languageCode;
    if (_locationLanguage == language) return;
    _locationLanguage = language;
    _locate(forceRefresh: true);
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

  Future<void> _locate({bool forceRefresh = false}) async {
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
      setState(() {
        _locationLabel = location.label;
        _hasResolvedLocation = true;
      });
      widget.onLocationChanged?.call(location);
    } on LocationFailure catch (error) {
      if (!mounted) return;
      setState(() => _locationLabel = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locationLabel = '定位失败，点击重试');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
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
                            onTap: _locating
                                ? null
                                : () => _locate(forceRefresh: true),
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
                                    const Padding(
                                      padding: EdgeInsets.only(right: 5),
                                      child: Icon(
                                        Icons.my_location,
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
                                  const Icon(Icons.refresh, size: 14),
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
              ? SliverToBoxAdapter(child: _LoadFailure(onRetry: widget.onRetry))
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
              child: Text(event.emoji, style: const TextStyle(fontSize: 42)),
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
              ? _LoadFailure(onRetry: widget.onRetry ?? () {})
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

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final full = e.joined >= e.capacity;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            expandedHeight: 235,
            pinned: true,
            backgroundColor: _mint,
            leading: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            actions: [
              IconButton.filledTonal(
                onPressed: () => setState(() => _saved = !_saved),
                icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border),
              ),
              const SizedBox(width: 12),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD7ECDF), Color(0xFFFFEED9)],
                  ),
                ),
                child: Text(e.emoji, style: const TextStyle(fontSize: 84)),
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
                    leading: const CircleAvatar(
                      radius: 25,
                      backgroundColor: Color(0xFFFFD9C5),
                      child: Text('🙂', style: TextStyle(fontSize: 24)),
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
                  Row(
                    children: [
                      for (var i = 0; i < e.joined.clamp(0, 6); i++)
                        Align(
                          widthFactor: .78,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors
                                .primaries[(i + e.id) % Colors.primaries.length]
                                .shade100,
                            child: Text(
                              [
                                '🧑🏻',
                                '👩🏻',
                                '👨🏻',
                                '🧑🏻‍🦱',
                                '👩🏻‍🦰',
                                '🧔🏻',
                              ][i],
                            ),
                          ),
                        ),
                    ],
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
                  onPressed: _joining || (e.isPast && !e.isOwned)
                      ? null
                      : e.isOwned
                      ? widget.onOpenMyActivities
                      : e.isJoined
                      ? () => _leave(e)
                      : () => _join(e, full),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: e.isJoined && !e.isOwned
                        ? Colors.grey.shade700
                        : _green,
                  ),
                  child: _joining
                      ? const _ButtonProgress(label: '提交中…')
                      : Text(
                          e.isOwned
                              ? '查看我的活动'
                              : e.isPast
                              ? context.tr('pastActivity')
                              : e.isJoined
                              ? '退出活动'
                              : full
                              ? '加入候补'
                              : e.approval
                              ? '申请参加'
                              : '立即参加',
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _join(EventItem e, bool full) async {
    setState(() => _joining = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() {
      _joining = false;
      if (!full && !e.approval) {
        e.isJoined = true;
        e.joined++;
      }
    });
    widget.onChanged();
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
                full ? Icons.hourglass_top : Icons.check,
                color: _green,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              full
                  ? '已加入候补'
                  : e.approval
                  ? '申请已提交'
                  : '参加成功！',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              full
                  ? '有名额释放时会按顺序自动递补并通知你'
                  : e.approval
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

  void _leave(EventItem e) {
    setState(() {
      e.isJoined = false;
      e.joined--;
    });
    widget.onChanged();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已退出活动')));
  }
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
  String _category = '户外';
  late Future<List<ActivityCategory>> _categoryFuture;
  late Future<List<AdministrativeRegion>> _regionFuture;
  String? _majorCategoryId;
  String? _leafCategoryId;
  int _capacity = 6;
  bool _approval = true;
  bool _publishing = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _cityCode;
  String? _districtCode;
  String _city = '';
  String _district = '';
  final _meetingPoint = TextEditingController();
  final _price = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _categoryFuture = widget.loadRemoteData
        ? CategoryService.load()
        : Future.value(const []);
    _regionFuture = widget.loadRemoteData
        ? RegionService.load()
        : Future.value(const []);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _meetingPoint.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _loadingSource
      ? const Center(child: CircularProgressIndicator())
      : _sourceFailed
      ? _LoadFailure(
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
      const FieldLabel('活动分类'),
      FutureBuilder<List<ActivityCategory>>(
        future: _categoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _InlineLoading(label: '正在加载活动分类…');
          }
          if (snapshot.hasError) {
            return _LoadFailure(
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
          var leaves = categories
              .where((item) => item.parentId == _majorCategoryId)
              .toList();
          if (!leaves.any((item) => item.id == _leafCategoryId)) {
            _leafCategoryId = leaves.isEmpty ? null : leaves.first.id;
          }
          final selected = leaves.where((item) => item.id == _leafCategoryId);
          if (selected.isNotEmpty) _category = selected.first.name;
          return Column(
            children: [
              _CategoryDropdown(
                label: '大分类',
                value: _majorCategoryId,
                items: majors,
                onChanged: (value) => setState(() {
                  _majorCategoryId = value;
                  _leafCategoryId = null;
                }),
              ),
              const SizedBox(height: 10),
              _CategoryDropdown(
                label: '小分类',
                value: _leafCategoryId,
                items: leaves,
                onChanged: (value) => setState(() => _leafCategoryId = value),
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
            return _LoadFailure(
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
                onChanged: (code) => setState(() => _districtCode = code),
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
      Card(
        child: SwitchListTile(
          value: _approval,
          onChanged: (v) => setState(() => _approval = v),
          title: const Text(
            '需要审核',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('申请者需经你确认后才能加入'),
        ),
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
    try {
      final token = AuthScope.of(context).token;
      if (token == null) throw Exception('登录已失效，请重新登录');
      await EventService.create(
        token: token,
        categoryId: _leafCategoryId!,
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
      if (!mounted) return;
      setState(() => _publishing = false);
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!mounted) return;
    widget.onCreated(
      EventItem(
        id: DateTime.now().millisecondsSinceEpoch,
        emoji: '✨',
        title: _title.text.trim(),
        category: _category,
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

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: _mint,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Icons.cloud_off_rounded, size: 42, color: _green),
          ),
          const SizedBox(height: 22),
          Text(
            context.tr('loadErrorTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('loadErrorMessage'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('retry')),
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
  const MessagesPage({required this.onReadAll, super.key});
  final VoidCallback onReadAll;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int _segment = 0;

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
                    '消息',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                TextButton(
                  onPressed: widget.onReadAll,
                  child: const Text('全部已读'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: 0, label: Text('活动群聊')),
                ButtonSegment(value: 1, label: Text('私信')),
                ButtonSegment(value: 2, label: Text('通知')),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ],
        ),
      ),
      Expanded(child: [_groups(), _direct(), _notices()][_segment]),
    ],
  );

  Widget _groups() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: [
      _ChatTile(
        emoji: '🌿',
        title: '汉江日落野餐局',
        message: '小满：集合点已更新，请大家查看',
        time: '10:24',
        unread: 2,
        onTap: () => _openChat('汉江日落野餐局'),
      ),
      _ChatTile(
        emoji: '🥾',
        title: '北汉山轻徒步',
        message: '阿泽：天气不错，周六见！',
        time: '昨天',
        onTap: () => _openChat('北汉山轻徒步'),
      ),
      _ChatTile(
        emoji: '🎲',
        title: '江南桌游夜',
        message: '系统：活动已取消',
        time: '周一',
        onTap: () => _openChat('江南桌游夜'),
      ),
    ],
  );

  Widget _direct() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: [
      _ChatTile(
        emoji: '🙂',
        title: '小满',
        message: '第一次参加也没问题～',
        time: '昨天',
        unread: 1,
        onTap: () => _openChat('小满'),
      ),
      _ChatTile(
        emoji: '🧑🏻',
        title: 'Eric',
        message: '好的，已收到你的申请',
        time: '周二',
        onTap: () => _openChat('Eric'),
      ),
    ],
  );

  Widget _notices() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: const [
      _NoticeTile(
        icon: Icons.how_to_reg,
        title: '申请已通过',
        subtitle: '你已加入「汉江日落野餐局」',
        time: '10分钟前',
      ),
      _NoticeTile(
        icon: Icons.location_on,
        title: '集合点已公开',
        subtitle: '组织者更新了准确集合地点',
        time: '1小时前',
      ),
      _NoticeTile(
        icon: Icons.rate_review_outlined,
        title: '等待评价',
        subtitle: '评价仅展示标签与信誉构成',
        time: '昨天',
      ),
    ],
  );

  void _openChat(String title) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ChatPage(title: title)));
  }
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
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 5),
    leading: CircleAvatar(
      backgroundColor: _mint,
      child: Icon(icon, color: _green),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: Text(
      time,
      style: const TextStyle(fontSize: 12, color: Colors.black45),
    ),
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({required this.title, super.key});
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final List<String> _sent = [];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const Text(
            '6 位成员 · 活动群',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
      ],
    ),
    body: Column(
      children: [
        Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _mint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.location_on_outlined, color: _green),
              SizedBox(width: 10),
              Expanded(child: Text('集合点已更新 · 汝矣渡口站 2 号出口')),
              Icon(Icons.chevron_right),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              const Center(child: _Pill('今天')),
              const SizedBox(height: 18),
              const _Bubble(text: '大家好，今晚天气不错，我们在 2 号出口集合～', mine: false),
              const _Bubble(text: '收到！需要带野餐垫吗？', mine: true),
              const _Bubble(text: '不用，我已经准备好了 😊', mine: false),
              ..._sent.map((m) => _Bubble(text: m, mine: true)),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      hintText: '发送消息…',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton.filled(
                  onPressed: _send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  void _send() {
    if (_input.text.trim().isEmpty) return;
    setState(() {
      _sent.add(_input.text.trim());
      _input.clear();
    });
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
      child: Text(text, style: TextStyle(color: mine ? Colors.white : _ink)),
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
        appBar: AppBar(title: Text(routeContext.tr('publishSimilar'))),
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
          return _LoadFailure(
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
        setState(() => _future = EventService.myActivities(widget.token));
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
                '${isPast ? '${context.tr('pastActivity')} · ' : ''}${row['title'] ?? ''}',
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
              onTap: () {
                if (widget.selectSource) {
                  Navigator.of(context).pop('${row['id']}');
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _MyActivityRecordPage(
                      activity: row,
                      token: widget.token,
                      isOrganizer: isOrganizer,
                    ),
                  ),
                );
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

class _MyActivityRecordPage extends StatelessWidget {
  const _MyActivityRecordPage({
    required this.activity,
    required this.token,
    required this.isOrganizer,
  });
  final Map<String, dynamic> activity;
  final String token;
  final bool isOrganizer;

  @override
  Widget build(BuildContext context) {
    final price = (activity['price_amount'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(isOrganizer ? context.tr('activityManagement') : '活动记录'),
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
              '${activity['event_status']} · 报名状态 ${activity['membership_status']}',
            ),
          ),
          if (isOrganizer) ...[
            FilledButton.icon(
              onPressed: () => _openSimilarEvent(context, '${activity['id']}'),
              icon: const Icon(Icons.copy_outlined),
              label: Text(context.tr('publishSimilar')),
            ),
            const Divider(height: 34),
            _OrganizerApplications(token: token, eventId: '${activity['id']}'),
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
              _LoadFailure(onRetry: _reload)
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${application['nickname'] ?? context.tr('applicant')}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${context.tr('partySize')}: $partySize · '
                        '${context.tr('trust')}: $trustScore',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${context.tr('applicationNote')}: $note'),
            ],
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
    appBar: AppBar(title: Text(title)),
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
    appBar: AppBar(title: const Text('安全中心')),
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
            FilledButton.icon(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              icon: const Icon(Icons.call),
              label: const Text('拨打 112（警方）'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.medical_services_outlined),
              label: const Text('拨打 119（消防急救）'),
            ),
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
