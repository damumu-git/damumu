enum SocialProvider { google, kakao }

class SocialCredential {
  const SocialCredential(this.provider, this.token);
  final SocialProvider provider;
  final String token;
}

class SocialLoginException implements Exception {
  const SocialLoginException(this.code);
  final String code;
}
