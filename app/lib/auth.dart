import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as parser;
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'l10n.dart';
import 'app_permissions.dart';
import 'login_preferences.dart';
import 'app_theme.dart';
import 'push_notification_service.dart';
import 'web_cropper_layout.dart';
import 'social_login.dart';
import 'social_registration.dart';

const _green = AppPalette.accent;
const _mint = AppPalette.soft;
const _ink = AppPalette.ink;
const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.damumu.com/api/v1',
);
const _devAutoLogin = bool.fromEnvironment(
  'DEV_AUTO_LOGIN',
  defaultValue: false,
);
const _devTestEmail = String.fromEnvironment(
  'DEV_TEST_EMAIL',
  defaultValue: 'tester@muda.local',
);
const _devTestPassword = String.fromEnvironment(
  'DEV_TEST_PASSWORD',
  defaultValue: 'MudaTest2026!',
);

class AuthUser {
  const AuthUser({
    required this.id,
    required this.nickname,
    required this.email,
    this.avatarUrl,
    this.avatarImageUrl,
  });

  final String id;
  final String nickname;
  final String email;
  final String? avatarUrl;
  final String? avatarImageUrl;

  AuthUser copyWith({
    String? nickname,
    String? avatarUrl,
    String? avatarImageUrl,
  }) => AuthUser(
    id: id,
    nickname: nickname ?? this.nickname,
    email: email,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    avatarImageUrl: avatarImageUrl ?? this.avatarImageUrl,
  );

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: '${json['id'] ?? json['userId']}',
    nickname: '${json['nickname'] ?? ''}',
    email: '${json['email'] ?? ''}',
    avatarUrl: json['avatarUrl'] as String?,
    avatarImageUrl: json['avatarImageUrl'] as String?,
  );
}

class AuthApiException implements Exception {
  const AuthApiException(
    this.statusCode,
    this.message, {
    this.code,
    this.traceId,
  });
  final int statusCode;
  final String message;
  final String? code;
  final String? traceId;
  @override
  String toString() => message;
}

class AuthApi {
  static Future<Map<String, dynamic>> _json(
    String path, {
    String method = 'GET',
    String? token,
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_apiBase$path'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    final response = await (() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    })().timeout(const Duration(seconds: 15));
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }
    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) decoded = value;
    } on FormatException {
      // Proxies may return an HTML or empty error response.
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded == null) {
      final error = decoded?['error'];
      final trace = response.headers['x-trace-id'] ?? decoded?['traceId'];
      final code = error is Map ? error['code'] : null;
      final message = error is Map ? error['message'] : null;
      throw AuthApiException(
        response.statusCode,
        message is String && response.statusCode < 500 ? message : '',
        code: code is String ? code : null,
        traceId:
            trace is String && RegExp(r'^[A-Za-z0-9:-]{1,80}$').hasMatch(trace)
            ? trace
            : null,
      );
    }
    return (decoded['data'] as Map?)?.cast<String, dynamic>() ?? decoded;
  }

  static Future<Map<String, dynamic>> login(String email, String password) =>
      _json(
        '/auth/login',
        method: 'POST',
        body: {'email': email, 'password': password},
      );

  static Future<Map<String, dynamic>> register(
    String nickname,
    String email,
    String password,
    String? avatarId, {
    required bool ageConfirmed,
    required bool privacyAcknowledged,
  }) => _json(
    '/auth/register',
    method: 'POST',
    body: {
      'nickname': nickname,
      'email': email,
      'password': password,
      'avatarId': avatarId,
      'ageConfirmed': ageConfirmed,
      'privacyAcknowledged': privacyAcknowledged,
      'privacyVersion': '2026-10-21',
    },
  );

  static Future<AuthUser> me(String token) async =>
      AuthUser.fromJson(await _json('/me', token: token));

  static Future<Map<String, dynamic>> social(
    SocialCredential credential, {
    String? nickname,
    String? locale,
  }) => _json(
    '/auth/social/${credential.provider.name}',
    method: 'POST',
    body: {
      'token': credential.token,
      if (nickname != null) ...{
        'nickname': nickname,
        'ageConfirmed': true,
        'privacyAcknowledged': true,
        'privacyVersion': '2026-10-21',
        'locale': locale,
      },
    },
  );

  static Future<void> deleteAccount(String token) async {
    await _json('/me', method: 'DELETE', token: token);
  }

  static Future<String> uploadAvatar(String token, Uint8List jpeg) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/me/avatar'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'avatar',
        jpeg,
        filename: 'avatar.jpg',
        contentType: parser.MediaType('image', 'jpeg'),
      ),
    );
    final response = await http.Response.fromStream(await request.send());
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? '头像上传失败');
    }
    return decoded['data']['avatarUrl'] as String;
  }

  static Future<List<SystemAvatarData>> systemAvatars(String locale) async {
    final response = await http.get(
      Uri.parse('$_apiBase/system-avatars?locale=$locale'),
    );
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?['message'] ?? 'Unable to load avatars');
    }
    return (decoded['data'] as List)
        .map((item) => SystemAvatarData.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class AuthController extends ChangeNotifier {
  AuthController();

  bool restoreFailed = false;
  bool _restoring = false;
  int _sessionVersion = 0;
  bool _persistSession = true;

  Future<void> _setAutoLogin(bool enabled) async {
    _persistSession = enabled;
    await (await SharedPreferences.getInstance()).setBool(
      LoginPreferences.autoKey,
      enabled,
    );
  }

  // This is only a local expiry hint. /me verifies the signature and account.
  bool get sessionExpired {
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return false;
    final expires = int.tryParse(parts[1]);
    return expires != null &&
        expires <= DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  Future<bool> loginSocial(
    SocialCredential credential, {
    String? nickname,
    String? locale,
    bool autoLogin = true,
  }) async {
    final result = await AuthApi.social(
      credential,
      nickname: nickname,
      locale: locale,
    );
    if (result['registrationRequired'] == true) return false;
    await _setAutoLogin(autoLogin);
    token = result['accessToken'] as String;
    user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveToken(token);
    notifyListeners();
    return true;
  }

  bool loading = true;
  AuthUser? user;
  String? token;

  Future<void> restore({bool background = false}) async {
    if (_restoring) return;
    _restoring = true;
    final version = _sessionVersion;
    final keepCurrentPage = background && user != null;
    loading = !keepCurrentPage;
    restoreFailed = false;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      if (version != _sessionVersion) return;
      _persistSession = preferences.getBool(LoginPreferences.autoKey) ?? true;
      // A non-persistent login remains valid while this app process is alive.
      token = background
          ? token
          : (_persistSession ? preferences.getString('auth_token') : null);
      if (!_persistSession) await preferences.remove('auth_token');
      if (token != null && sessionExpired) {
        await _discardSession();
      } else if (token != null) {
        try {
          final restored = await AuthApi.me(token!);
          if (version != _sessionVersion) return;
          user = restored;
        } catch (error) {
          if (version != _sessionVersion) return;
          if (error is AuthApiException &&
              const [401, 403, 404].contains(error.statusCode)) {
            await _discardSession();
          } else {
            // Offline/timeout/server failure does not revoke a valid session.
            restoreFailed = !keepCurrentPage;
            if (!keepCurrentPage) user = null;
          }
        }
      }
      if (user == null && token == null && _devAutoLogin) {
        try {
          final result = await AuthApi.login(_devTestEmail, _devTestPassword);
          if (version != _sessionVersion) return;
          token = result['accessToken'] as String;
          user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
          await _saveToken(token);
        } catch (_) {
          // Explicit development-only opt-in; never used in release by default.
        }
      }
    } finally {
      _restoring = false;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _discardSession() async {
    await _clearPrivateLocalData(user?.id);
    user = null;
    token = null;
    restoreFailed = false;
    await _saveToken(null);
  }

  Future<void> login(
    String email,
    String password, {
    bool autoLogin = true,
    bool rememberId = false,
  }) async {
    final result = await AuthApi.login(email.trim(), password);
    await _setAutoLogin(autoLogin);
    await LoginPreferences.saveId(email, rememberId);
    token = result['accessToken'] as String;
    user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveToken(token);
    notifyListeners();
  }

  Future<void> register(
    String nickname,
    String email,
    String password,
    String? avatarId, {
    required bool ageConfirmed,
    required bool privacyAcknowledged,
  }) async {
    final result = await AuthApi.register(
      nickname.trim(),
      email.trim(),
      password,
      avatarId,
      ageConfirmed: ageConfirmed,
      privacyAcknowledged: privacyAcknowledged,
    );
    await _setAutoLogin(true);
    token = result['accessToken'] as String;
    user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveToken(token);
    notifyListeners();
  }

  Future<void> updateAvatar(Uint8List bytes) async {
    final url = await AuthApi.uploadAvatar(token!, bytes);
    user = user!.copyWith(avatarUrl: url, avatarImageUrl: url);
    notifyListeners();
  }

  Future<void> setSystemAvatar(SystemAvatarData avatar) async {
    final result = await AuthApi._json(
      '/me/avatar/system',
      method: 'PUT',
      token: token,
      body: {'avatarId': avatar.id},
    );
    user = user!.copyWith(
      avatarUrl: result['avatarUrl'] as String?,
      avatarImageUrl: result['avatarImageUrl'] as String?,
    );
    notifyListeners();
  }

  Future<void> logout() async {
    _sessionVersion++;
    final previousToken = token;
    await _discardSession();
    loading = false;
    notifyListeners();
    try {
      await PushNotificationService.instance.stop(previousToken);
    } catch (_) {
      // Local logout must complete even if push cleanup fails.
    }
  }

  Future<void> deleteAccount() async {
    final currentToken = token;
    if (currentToken == null) throw StateError('Missing authentication token');
    await AuthApi.deleteAccount(currentToken);
    await LoginPreferences.saveId('', false);
    _sessionVersion++;
    restoreFailed = false;
    await _clearPrivateLocalData(user?.id);
    try {
      await PushNotificationService.instance.stop(currentToken);
    } catch (_) {
      // The server accepted the deletion request. Local sign-out must still
      // complete even if unregistering a push token fails.
    }
    user = null;
    token = null;
    await _saveToken(null);
    notifyListeners();
  }

  Future<void> _saveToken(String? value) async {
    final preferences = await SharedPreferences.getInstance();
    value == null || !_persistSession
        ? await preferences.remove('auth_token')
        : await preferences.setString('auth_token', value);
  }

  Future<void> _clearPrivateLocalData(String? userId) async {
    if (userId != null) {
      final preferences = await SharedPreferences.getInstance();
      for (final key
          in preferences
              .getKeys()
              .where(
                (key) =>
                    key.startsWith('chat_cache_${userId}_') ||
                    key.startsWith('chat_pending_${userId}_'),
              )
              .toList()) {
        await preferences.remove(key);
      }
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()!.notifier!;
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authenticatedBuilder});
  final WidgetBuilder authenticatedBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _controller = AuthController();

  @override
  void initState() {
    super.initState();
    _controller.restore();
  }

  @override
  Widget build(BuildContext context) => AuthScope(
    controller: _controller,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_controller.restoreFailed) {
          return SessionRecovery(controller: _controller);
        }
        return _controller.user == null
            ? const AuthPage()
            : widget.authenticatedBuilder(context);
      },
    ),
  );
}

class SessionRecovery extends StatelessWidget {
  const SessionRecovery({super.key, required this.controller});
  final AuthController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: _green),
            const SizedBox(height: 16),
            Text(
              context.tr('sessionRestoreFailed'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: controller.restore,
              child: Text(context.tr('retry')),
            ),
            TextButton(
              onPressed: controller.logout,
              child: Text(context.tr('logout')),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.avatarLoader, this.socialAuthorize});
  final Future<List<SystemAvatarData>> Function(String locale)? avatarLoader;
  final Future<SocialCredential?> Function(SocialProvider provider)?
  socialAuthorize;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _autoLogin = true;
  bool _rememberId = false;
  bool _optionsLoaded = false;
  bool _busy = false;
  bool _obscure = true;
  bool _ageConfirmed = false;
  bool _privacyAcknowledged = false;
  String? _avatarId;
  late Future<List<SystemAvatarData>> _avatars;

  @override
  void initState() {
    super.initState();
    _avatars = (widget.avatarLoader ?? AuthApi.systemAvatars)('zh');
    _loadLoginOptions();
  }

  Future<void> _loadLoginOptions() async {
    final options = await LoginPreferences.load();
    if (!mounted) return;
    setState(() {
      _autoLogin = options.autoLogin;
      _rememberId = options.rememberId;
      if (_email.text.isEmpty) _email.text = options.email;
      _optionsLoaded = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    _avatars = (widget.avatarLoader ?? AuthApi.systemAvatars)(locale);
  }

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/branding/logo.png',
                        width: 64,
                        height: 64,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _register
                        ? context.tr('createAccount')
                        : context.tr('welcomeBack'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _register
                        ? context.tr('registerSubtitle')
                        : context.tr('loginSubtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    Text(
                      context.tr('chooseAvatar'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<SystemAvatarData>>(
                      future: _avatars,
                      builder: (context, snapshot) {
                        final avatars = snapshot.data ?? const [];
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 68,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (avatars.isEmpty) {
                          return SizedBox(
                            height: 50,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(context.tr('noAvatars')),
                            ),
                          );
                        }
                        _avatarId ??= avatars.first.id;
                        return SizedBox(
                          height: 68,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: avatars.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 9),
                            itemBuilder: (_, index) {
                              final avatar = avatars[index];
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _avatarId = avatar.id),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _avatarId == avatar.id
                                          ? _green
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                  child: SystemAvatar(
                                    avatar: avatar,
                                    radius: 27,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nickname,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: context.tr('nickname'),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? context.tr('nicknameError')
                          : null,
                    ),
                    const SizedBox(height: 13),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: context.tr('email'),
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : context.tr('emailError'),
                  ),
                  const SizedBox(height: 13),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      return password.length < 8 ||
                              !RegExp(r'[A-Za-z]').hasMatch(password) ||
                              !RegExp(r'\d').hasMatch(password)
                          ? context.tr('passwordError')
                          : null;
                    },
                  ),
                  if (!_register) ...[
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final options = [
                          _LoginOption(
                            key: const Key('auto-login-option'),
                            label: context.tr('autoLogin30Days'),
                            value: _autoLogin,
                            onChanged: _busy || !_optionsLoaded
                                ? null
                                : (value) => setState(() => _autoLogin = value),
                          ),
                          _LoginOption(
                            key: const Key('remember-id-option'),
                            label: context.tr('rememberId'),
                            value: _rememberId,
                            onChanged: _busy || !_optionsLoaded
                                ? null
                                : (value) async {
                                    setState(() => _rememberId = value);
                                    // Unchecking removes the previously remembered ID immediately.
                                    if (!value) {
                                      await LoginPreferences.saveId('', false);
                                    }
                                  },
                          ),
                        ];
                        if (constraints.maxWidth < 340 ||
                            Localizations.localeOf(context).languageCode ==
                                'en' ||
                            MediaQuery.textScalerOf(context).scale(14) > 18) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              options[0],
                              const SizedBox(height: 8),
                              options[1],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: options[0]),
                            const SizedBox(width: 10),
                            Expanded(child: options[1]),
                          ],
                        );
                      },
                    ),
                  ],
                  if (_register) ...[
                    CheckboxListTile(
                      value: _ageConfirmed,
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _ageConfirmed = value ?? false),
                      title: Text(context.tr('minimumAgeConfirmation')),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      value: _privacyAcknowledged,
                      onChanged: _busy
                          ? null
                          : (value) => setState(
                              () => _privacyAcknowledged = value ?? false,
                            ),
                      title: Text(context.tr('privacyNoticeAcknowledgement')),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? 'https://www.damumu.com/privacy-ko.html'
                              : 'https://www.damumu.com/privacy.html',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(context.tr('readPrivacyNotice')),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _register
                                ? context.tr('registerAction')
                                : context.tr('loginAction'),
                          ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _register = !_register),
                    child: Text(
                      _register
                          ? context.tr('goLogin')
                          : context.tr('goRegister'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(context.tr('socialOr'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _social(SocialProvider.google),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1F1F1F),
                      side: const BorderSide(color: Color(0xFF747775)),
                      textStyle: const TextStyle(
                        fontFamily: AppTypography.family,
                        fontFamilyFallback: AppTypography.fallback,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    icon: Image.asset(
                      'assets/auth/google-g.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                    label: Text(context.tr('googleLogin')),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191919),
                    ),
                    onPressed: _busy
                        ? null
                        : () => _social(SocialProvider.kakao),
                    icon: SvgPicture.asset(
                      'assets/images/icon_talk_login.svg',
                      package: 'kakao_flutter_sdk_user',
                      width: 20,
                      height: 20,
                      excludeFromSemantics: true,
                    ),
                    label: Text(context.tr('kakaoLogin')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _social(SocialProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final credential =
          await (widget.socialAuthorize ?? SocialLogin.authorize)(provider);
      if (credential == null || !mounted) return;
      final auth = AuthScope.of(context);
      final locale = Localizations.localeOf(context).languageCode;
      if (await auth.loginSocial(credential, autoLogin: _autoLogin)) return;
      if (!mounted) return;
      setState(() => _busy = false);
      final nickname = await showDialog<String>(
        context: context,
        builder: (_) => const SocialRegistrationDialog(),
      );
      if (nickname == null || !mounted) return;
      setState(() => _busy = true);
      await auth.loginSocial(
        credential,
        nickname: nickname,
        locale: locale,
        autoLogin: _autoLogin,
      );
    } on SocialLoginException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr(error.code))));
      }
    } catch (error) {
      if (mounted) _showAuthFailure(error, fallback: 'socialFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_register && (!_ageConfirmed || !_privacyAcknowledged)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('registrationConfirmationRequired'))),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final auth = AuthScope.of(context);
      if (_register) {
        await auth.register(
          _nickname.text,
          _email.text,
          _password.text,
          _avatarId,
          ageConfirmed: _ageConfirmed,
          privacyAcknowledged: _privacyAcknowledged,
        );
      } else {
        await auth.login(
          _email.text,
          _password.text,
          autoLogin: _autoLogin,
          rememberId: _rememberId,
        );
      }
    } catch (error) {
      if (mounted) _showAuthFailure(error, fallback: 'authRequestFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showAuthFailure(Object error, {required String fallback}) {
    final failure = error is AuthApiException ? error : null;
    final message = switch (failure?.code) {
      'social_login_unavailable' => context.tr('socialUnavailable'),
      _ when failure != null && failure.message.isNotEmpty => failure.message,
      _ => context.tr(fallback),
    };
    final traceId = failure?.traceId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          traceId == null
              ? message
              : '$message\n${context.tr('authTraceId')} $traceId',
        ),
        duration: traceId == null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 8),
      ),
    );
  }
}

class _LoginOption extends StatelessWidget {
  const _LoginOption({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    decoration: BoxDecoration(
      color: value ? AppPalette.soft : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: value ? AppPalette.primary : AppPalette.line),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged == null
            ? null
            : (selected) => onChanged!(selected ?? false),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
        side: const BorderSide(color: AppPalette.accent, width: 1.5),
        activeColor: AppPalette.accent,
        checkColor: Colors.white,
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppPalette.ink,
          ),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
    ),
  );
}

class SystemAvatarData {
  const SystemAvatarData({
    required this.id,
    required this.code,
    required this.name,
    required this.imageUrl,
  });

  final String id;
  final String code;
  final String name;
  final String imageUrl;

  factory SystemAvatarData.fromJson(Map<String, dynamic> json) =>
      SystemAvatarData(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
      );
}

class SystemAvatar extends StatelessWidget {
  const SystemAvatar({super.key, required this.avatar, required this.radius});
  final SystemAvatarData avatar;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: _mint,
    backgroundImage: NetworkImage(absoluteImageUrl(avatar.imageUrl)),
  );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 34});
  final AuthUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final value = user.avatarImageUrl;
    if (value != null && value.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: _mint,
        backgroundImage: NetworkImage(absoluteImageUrl(value)),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _mint,
      child: const Icon(Icons.person_rounded, color: _green),
    );
  }
}

String absoluteImageUrl(String value) =>
    value.startsWith('http') ? value : '${Uri.parse(_apiBase).origin}$value';

Map<String, String>? privateImageHeaders(BuildContext context, String value) {
  final image = Uri.tryParse(absoluteImageUrl(value));
  if (image == null ||
      (image.scheme != 'http' && image.scheme != 'https') ||
      image.origin != Uri.parse(_apiBase).origin ||
      !image.path.startsWith('/uploads/messages/')) {
    return null;
  }
  final token = context
      .dependOnInheritedWidgetOfExactType<AuthScope>()
      ?.notifier
      ?.token;
  return token == null ? null : {'Authorization': 'Bearer $token'};
}

Future<void> showAvatarEditor(BuildContext context) async {
  final auth = AuthScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetContext.tr('changeAvatar'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              sheetContext.tr('avatarRule'),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _AvatarSourceButton(
                    icon: Icons.camera_alt_outlined,
                    label: sheetContext.tr('takePhoto'),
                    onTap: () =>
                        _pickAvatar(sheetContext, auth, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AvatarSourceButton(
                    icon: Icons.photo_library_outlined,
                    label: sheetContext.tr('choosePhoto'),
                    onTap: () =>
                        _pickAvatar(sheetContext, auth, ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              sheetContext.tr('systemAvatar'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<SystemAvatarData>>(
              future: AuthApi.systemAvatars(
                Localizations.localeOf(sheetContext).languageCode,
              ),
              builder: (context, snapshot) {
                final avatars = snapshot.data ?? const [];
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (avatars.isEmpty) return Text(context.tr('noAvatars'));
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: avatars
                      .map(
                        (avatar) => Tooltip(
                          message: avatar.name,
                          child: GestureDetector(
                            onTap: () async {
                              await auth.setSystemAvatar(avatar);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                            child: SystemAvatar(avatar: avatar, radius: 27),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarSourceButton extends StatelessWidget {
  const _AvatarSourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(label),
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
  );
}

Future<void> _pickAvatar(
  BuildContext sheetContext,
  AuthController auth,
  ImageSource source,
) async {
  final cropTitle = sheetContext.tr('cropAvatar');
  final invalidImage = sheetContext.tr('invalidImage');
  final avatarTooLarge = sheetContext.tr('avatarTooLarge');
  final networkUnavailable = sheetContext.tr('networkUnavailable');
  var uploading = false;
  try {
    if (!await AppPermissions.ensureImage(sheetContext, source) ||
        !sheetContext.mounted) {
      return;
    }
    final picked = await ImagePicker().pickImage(
      requestFullMetadata: false,
      source: source,
      maxWidth: 1536,
      maxHeight: 1536,
      imageQuality: 90,
    );
    if (picked == null) return;
    if (await picked.length() > 128 * 1024 * 1024) {
      throw const FormatException('largePhotoProcessingFailed');
    }
    if (!sheetContext.mounted) return;
    final webLayout = webCropperLayout(sheetContext);
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 88,
      maxWidth: 1024,
      maxHeight: 1024,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: cropTitle,
          toolbarColor: _green,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: cropTitle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: sheetContext,
          presentStyle: webLayout.presentStyle,
          viewwMode: WebViewMode.mode_1,
          guides: true,
          rotatable: true,
          size: webLayout.size,
          translations: WebTranslations(
            title: cropTitle,
            rotateLeftTooltip: '向左旋转',
            rotateRightTooltip: '向右旋转',
            cancelButton: '取消',
            cropButton: '确认裁剪',
          ),
          themeData: const WebThemeData(rotateIconColor: _green),
        ),
      ],
    );
    if (cropped == null) return;
    final decoded = img.decodeImage(await cropped.readAsBytes());
    if (decoded == null) throw Exception(invalidImage);
    final square = img.copyResizeCropSquare(decoded, size: 512);
    var bytes = Uint8List.fromList(img.encodeJpg(square, quality: 86));
    if (bytes.length > 1024 * 1024) {
      throw Exception(avatarTooLarge);
    }
    if (!sheetContext.mounted) return;
    final confirmed = await showDialog<Uint8List>(
      context: sheetContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updatePreview) => AlertDialog(
          title: Text(dialogContext.tr('avatarPreview')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.memory(
                  bytes,
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
              TextButton.icon(
                onPressed: () => updatePreview(() {
                  final image = img.decodeJpg(bytes);
                  if (image != null) {
                    bytes = Uint8List.fromList(
                      img.encodeJpg(img.flipHorizontal(image), quality: 86),
                    );
                  }
                }),
                icon: const Icon(Icons.flip),
                label: Text(dialogContext.tr('flipPhoto')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dialogContext.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, bytes),
              child: Text(dialogContext.tr('confirmPhoto')),
            ),
          ],
        ),
      ),
    );
    if (confirmed == null) return;
    if (confirmed.length > 1024 * 1024) throw Exception(avatarTooLarge);
    uploading = true;
    await auth.updateAvatar(confirmed);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  } on SocketException {
    if (!sheetContext.mounted) return;
    _showError(sheetContext, networkUnavailable);
  } catch (error) {
    if (!sheetContext.mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '');
    _showError(
      sheetContext,
      uploading
          ? sheetContext.tr('avatarUploadFailed')
          : message == invalidImage || message == avatarTooLarge
          ? message
          : sheetContext.tr('largePhotoProcessingFailed'),
    );
  }
}

void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
