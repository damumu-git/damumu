import 'social_login_native.dart'
    if (dart.library.js_interop) 'social_login_stub.dart'
    as platform;
import 'social_login_types.dart';

export 'social_login_types.dart';

abstract final class SocialLogin {
  static Future<SocialCredential?> authorize(SocialProvider provider) =>
      platform.authorize(provider);
}
