import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_permissions.dart';
import 'app_theme.dart';
import 'l10n.dart';

const onboardingCompletedKey = 'onboarding_completed_v1';

class FirstRunGate extends StatefulWidget {
  const FirstRunGate({super.key, required this.onReady, required this.builder});
  final Future<void> Function() onReady;
  final WidgetBuilder builder;
  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  bool? _required;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    // Existing signed-in installations keep their session and can review in Settings.
    final required =
        preferences.getBool(onboardingCompletedKey) != true &&
        preferences.getString('auth_token') == null;
    if (!required && preferences.getBool(onboardingCompletedKey) != true) {
      await preferences.setBool(onboardingCompletedKey, true);
    }
    if (!mounted) return;
    setState(() => _required = required);
    if (!required) await widget.onReady();
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _required = false);
    await widget.onReady();
  }

  @override
  Widget build(BuildContext context) => switch (_required) {
    null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    true => OnboardingPage(onFinished: _finish),
    false => widget.builder(context),
  };
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onFinished,
    this.review = false,
    this.onChoiceChanged,
    this.requestPermission = AppPermissions.request,
  });
  final Future<void> Function() onFinished;
  final bool review;
  final Future<void> Function(AppPermission, bool)? onChoiceChanged;
  final Future<PermissionOutcome> Function(AppPermission) requestPermission;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pages = PageController();
  final _choices = <AppPermission, bool>{};
  final _outcomes = <AppPermission, PermissionOutcome>{};
  int _index = 0;
  bool _busy = false;
  static const _permissions = [
    AppPermission.camera,
    AppPermission.photos,
    AppPermission.notifications,
    AppPermission.location,
  ];
  static const _icons = [
    Icons.explore_outlined,
    Icons.camera_alt_outlined,
    Icons.photo_library_outlined,
    Icons.notifications_none_rounded,
    Icons.near_me_outlined,
    Icons.check_circle_outline_rounded,
  ];
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  AppPermission? _permissionAt(int page) =>
      page > 0 && page < 5 ? _permissions[page - 1] : null;
  int get _lastAvailablePage {
    for (var page = 1; page < 5; page++) {
      if (!_choices.containsKey(_permissionAt(page))) return page;
    }
    return 5;
  }

  bool get _canAdvance =>
      _permissionAt(_index) == null ||
      _choices.containsKey(_permissionAt(_index));

  Future<void> _choose(AppPermission permission, bool accepted) async {
    if (_busy) return;
    final selectedPage = _index;
    setState(() => _busy = true);
    try {
      PermissionOutcome? outcome;
      if (accepted) {
        outcome = await widget.requestPermission(permission);
      } else {
        await AppPermissions.decline(permission);
      }
      await widget.onChoiceChanged?.call(
        permission,
        accepted &&
            (outcome == PermissionOutcome.granted ||
                outcome == PermissionOutcome.selectedOnly),
      );
      if (!mounted) return;
      setState(() {
        _choices[permission] = accepted;
        if (outcome != null) {
          _outcomes[permission] = outcome;
        } else {
          _outcomes.remove(permission);
        }
      });
      if (outcome != PermissionOutcome.failed) {
        if (outcome == PermissionOutcome.denied ||
            outcome == PermissionOutcome.settings) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('permission_${outcome!.name}')),
              action: outcome == PermissionOutcome.settings
                  ? SnackBarAction(
                      label: context.tr('permissionOpenSettings'),
                      onPressed: Geolocator.openAppSettings,
                    )
                  : null,
            ),
          );
        }
        await _pages.animateToPage(
          selectedPage + 1,
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeInOutCubic,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _outcomes[permission] = PermissionOutcome.failed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    if (_busy || !_canAdvance) return;
    if (_index < 5) {
      await _pages.nextPage(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(
        onboardingCompletedKey,
        true,
      );
      await widget.onFinished();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('permissionSaveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppPalette.background,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/branding/logo.png',
                      width: 36,
                      height: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('introBrand'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_index + 1} / 6',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  ignoring: _busy,
                  child: PageView.builder(
                    controller: _pages,
                    physics: _PermissionPagePhysics(
                      lastPage: () => _lastAvailablePage,
                    ),
                    itemCount: 6,
                    onPageChanged: (page) => setState(() => _index = page),
                    itemBuilder: (context, page) => _page(context, page),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        6,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 24 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppPalette.accent
                                : AppPalette.line,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (_index > 0) ...[
                          IconButton(
                            onPressed: _busy
                                ? null
                                : () => _pages.previousPage(
                                    duration: const Duration(milliseconds: 340),
                                    curve: Curves.easeInOutCubic,
                                  ),
                            tooltip: context.tr('introBack'),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: FilledButton(
                            onPressed: !_busy && _canAdvance ? _next : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                context.tr(
                                  _index == 5
                                      ? (widget.review
                                            ? 'introDone'
                                            : 'introStart')
                                      : 'introNext',
                                ),
                              ),
                            ),
                          ),
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
    ),
  );

  Widget _page(BuildContext context, int page) {
    final permission = _permissionAt(page);
    final name = permission?.name ?? (page == 0 ? 'welcome' : 'ready');
    final outcome = permission == null ? null : _outcomes[permission];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                color: AppPalette.soft,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(_icons[page], size: 64, color: AppPalette.accent),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            context.tr('intro_${name}_title'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('intro_${name}_body'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppPalette.line),
            ),
            child: Text(
              context.tr(
                permission == null ? 'introOptional' : 'intro_${name}_fallback',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
          if (permission == AppPermission.notifications) ...[
            const SizedBox(height: 12),
            Text(
              context.tr('introPushSeparate'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (permission != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: _busy ? null : () => _choose(permission, true),
              child: Text(context.tr('permissionAgree')),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _busy ? null : () => _choose(permission, false),
              child: Text(context.tr('permissionDecline')),
            ),
            if (_choices.containsKey(permission) || outcome != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(
                  context.tr(
                    outcome == null
                        ? 'permissionSkipped'
                        : 'permission_${outcome.name}',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
            if (outcome == PermissionOutcome.settings)
              TextButton(
                onPressed: _busy ? null : Geolocator.openAppSettings,
                child: Text(context.tr('permissionOpenSettings')),
              ),
          ],
          if (page == 5) ...[
            const SizedBox(height: 12),
            ..._permissions.map(
              (p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _choices[p] == true &&
                          (_outcomes[p] == PermissionOutcome.granted ||
                              _outcomes[p] == PermissionOutcome.selectedOnly)
                      ? Icons.check_circle_outline
                      : Icons.remove_circle_outline,
                  color: AppPalette.accent,
                ),
                title: Text(context.tr('intro_${p.name}_title')),
                subtitle: Text(
                  context.tr(
                    _outcomes[p] == null
                        ? 'permissionSkipped'
                        : 'permission_${_outcomes[p]!.name}',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Bound the gesture before it crosses an unanswered page, instead of snapping
// the viewport back from onPageChanged. PageView retains its native page snap.
class _PermissionPagePhysics extends ClampingScrollPhysics {
  const _PermissionPagePhysics({required this.lastPage, super.parent});
  final int Function() lastPage;
  @override
  _PermissionPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _PermissionPagePhysics(lastPage: lastPage, parent: buildParent(ancestor));
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final limit = lastPage() * position.viewportDimension;
    if (value > limit && value > position.pixels) {
      return value - (position.pixels > limit ? position.pixels : limit);
    }
    return super.applyBoundaryConditions(position, value);
  }
}
