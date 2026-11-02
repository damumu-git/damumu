import 'social_login_types.dart';

Future<SocialCredential?> authorize(SocialProvider provider) async =>
    throw const SocialLoginException('socialWebUnavailable');
