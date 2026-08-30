import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';

const _green = Color(0xFF1F7A55);
const _mint = Color(0xFFE7F4EC);
const _ink = Color(0xFF17211B);
const _apiBase = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);
const _devAutoLogin = bool.fromEnvironment(
  'DEV_AUTO_LOGIN',
  defaultValue: kDebugMode,
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
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw Exception(error?['message'] ?? '请求失败，请稍后重试');
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
    String? avatarId,
  ) => _json(
    '/auth/register',
    method: 'POST',
    body: {
      'nickname': nickname,
      'email': email,
      'password': password,
      'avatarId': avatarId,
    },
  );

  static Future<AuthUser> me(String token) async =>
      AuthUser.fromJson(await _json('/me', token: token));

  static Future<String> uploadAvatar(String token, Uint8List jpeg) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/me/avatar'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('avatar', jpeg, filename: 'avatar.jpg'),
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

  bool loading = true;
  AuthUser? user;
  String? token;

  Future<void> restore() async {
    token = (await SharedPreferences.getInstance()).getString('auth_token');
    if (token != null) {
      try {
        user = await AuthApi.me(token!);
      } catch (_) {
        await _saveToken(null);
      }
    }
    if (user == null && _devAutoLogin) {
      try {
        final result = await AuthApi.login(_devTestEmail, _devTestPassword);
        token = result['accessToken'] as String;
        user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
        await _saveToken(token);
      } catch (_) {
        // Keep the regular login page available when the local API is offline
        // or the development seed account has not been created yet.
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final result = await AuthApi.login(email.trim(), password);
    token = result['accessToken'] as String;
    user = AuthUser.fromJson(result['user'] as Map<String, dynamic>);
    await _saveToken(token);
    notifyListeners();
  }

  Future<void> register(
    String nickname,
    String email,
    String password,
    String? avatarId,
  ) async {
    final result = await AuthApi.register(
      nickname.trim(),
      email.trim(),
      password,
      avatarId,
    );
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
    user = null;
    token = null;
    await _saveToken(null);
    notifyListeners();
  }

  Future<void> _saveToken(String? value) async {
    final preferences = await SharedPreferences.getInstance();
    value == null
        ? await preferences.remove('auth_token')
        : await preferences.setString('auth_token', value);
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
        return _controller.user == null
            ? const AuthPage()
            : widget.authenticatedBuilder(context);
      },
    ),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.avatarLoader});
  final Future<List<SystemAvatarData>> Function(String locale)? avatarLoader;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _avatarId;
  late Future<List<SystemAvatarData>> _avatars;

  @override
  void initState() {
    super.initState();
    _avatars = (widget.avatarLoader ?? AuthApi.systemAvatars)('zh');
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
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: _green,
                    child: Icon(Icons.people_alt_rounded, color: Colors.white),
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
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final auth = AuthScope.of(context);
      if (_register) {
        await auth.register(
          _nickname.text,
          _email.text,
          _password.text,
          _avatarId,
        );
      } else {
        await auth.login(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
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
  try {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    if (!sheetContext.mounted) return;
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
          size: CropperSize(
            width: MediaQuery.sizeOf(
              sheetContext,
            ).width.clamp(320, 720).round(),
            height: 520,
          ),
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
    final bytes = Uint8List.fromList(img.encodeJpg(square, quality: 86));
    if (bytes.length > 1024 * 1024) {
      throw Exception(avatarTooLarge);
    }
    await auth.updateAvatar(bytes);
    if (sheetContext.mounted) Navigator.pop(sheetContext);
  } on SocketException {
    if (!sheetContext.mounted) return;
    _showError(sheetContext, networkUnavailable);
  } catch (error) {
    if (!sheetContext.mounted) return;
    _showError(sheetContext, error.toString().replaceFirst('Exception: ', ''));
  }
}

void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
