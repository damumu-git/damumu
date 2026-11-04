import 'package:shared_preferences/shared_preferences.dart';

class LoginPreferences {
  const LoginPreferences({
    this.autoLogin = true,
    this.rememberId = false,
    this.email = '',
  });
  final bool autoLogin;
  final bool rememberId;
  final String email;
  static const autoKey = 'login_auto_30_days_v1';
  static const rememberKey = 'login_remember_id_v1';
  static const emailKey = 'login_remembered_email_v1';

  static Future<LoginPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final remember = preferences.getBool(rememberKey) ?? false;
    return LoginPreferences(
      autoLogin: preferences.getBool(autoKey) ?? true,
      rememberId: remember,
      email: remember ? preferences.getString(emailKey) ?? '' : '',
    );
  }

  static Future<void> saveId(String email, bool remember) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(rememberKey, remember);
    if (remember) {
      await preferences.setString(emailKey, email.trim());
    } else {
      await preferences.remove(emailKey);
    }
  }
}
