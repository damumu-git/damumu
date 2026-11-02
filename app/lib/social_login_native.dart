import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'social_login_types.dart';

const _enabled = bool.fromEnvironment('SOCIAL_LOGIN_ENABLED');
const _googleServerId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
const _googleIosId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const _kakaoKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
Future<void>? _googleReady;
Future<void>? _kakaoReady;

Future<SocialCredential?> authorize(SocialProvider provider) async {
  if (!_enabled ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    throw const SocialLoginException('socialUnavailable');
  }
  if (provider == SocialProvider.google) {
    if (_googleServerId.isEmpty ||
        (defaultTargetPlatform == TargetPlatform.iOS && _googleIosId.isEmpty)) {
      throw const SocialLoginException('socialUnavailable');
    }
    try {
      await (_googleReady ??= GoogleSignIn.instance.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? _googleIosId
            : null,
        serverClientId: _googleServerId,
      ));
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const SocialLoginException('socialFailed');
      }
      return SocialCredential(provider, token);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const SocialLoginException('socialFailed');
    } finally {
      // The API uses its own local session. No Google refresh token is retained.
      if (_googleReady != null) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
    }
  }
  if (_kakaoKey.isEmpty) throw const SocialLoginException('socialUnavailable');
  try {
    await (_kakaoReady ??= kakao.KakaoSdk.init(
      nativeAppKey: _kakaoKey,
      loggingEnabled: false,
    ));
    final kakao.OAuthToken token;
    if (await kakao.isKakaoTalkInstalled()) {
      try {
        token = await kakao.UserApi.instance.loginWithKakaoTalk();
      } on kakao.KakaoClientException catch (error) {
        if (error.reason == kakao.ClientErrorCause.cancelled) return null;
        // Kakao Talk could not launch; allow browser account login instead.
        return SocialCredential(
          provider,
          (await kakao.UserApi.instance.loginWithKakaoAccount()).accessToken,
        );
      }
    } else {
      token = await kakao.UserApi.instance.loginWithKakaoAccount();
    }
    return SocialCredential(provider, token.accessToken);
  } on kakao.KakaoClientException catch (error) {
    if (error.reason == kakao.ClientErrorCause.cancelled) return null;
    throw const SocialLoginException('socialFailed');
  } catch (_) {
    throw const SocialLoginException('socialFailed');
  } finally {
    if (_kakaoReady != null) {
      try {
        await kakao.TokenManagerProvider.instance.manager.clear();
      } catch (_) {}
    }
  }
}
