import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleScope extends InheritedWidget {
  const AppLocaleScope({
    super.key,
    required this.locale,
    required this.onChanged,
    required super.child,
  });

  final Locale locale;
  final ValueChanged<Locale> onChanged;

  static AppLocaleScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLocaleScope>()!;

  static Future<Locale> restore() async {
    final code = (await SharedPreferences.getInstance()).getString(
      'app_locale',
    );
    return Locale(supportedCodes.contains(code) ? code! : 'zh');
  }

  static const supportedCodes = {'zh', 'en', 'ko'};

  @override
  bool updateShouldNotify(AppLocaleScope oldWidget) =>
      locale != oldWidget.locale;
}

extension AppTranslations on BuildContext {
  String tr(String key) {
    final language = Localizations.localeOf(this).languageCode;
    return (_strings[language] ?? _strings['zh']!)[key] ??
        _strings['zh']![key] ??
        key;
  }
}

const languageLabels = {'zh': '中文', 'en': 'English', 'ko': '한국어'};

const _strings = <String, Map<String, String>>{
  'zh': {
    'appName': '搭慕慕',
    'createAccount': '创建你的搭慕慕账号',
    'welcomeBack': '欢迎回来',
    'registerSubtitle': '认识新朋友，从一张喜欢的头像开始',
    'loginSubtitle': '登录后继续发现身边的活动',
    'chooseAvatar': '选择系统头像',
    'nickname': '昵称',
    'email': '邮箱',
    'password': '密码',
    'nicknameError': '昵称至少需要 2 个字符',
    'emailError': '请输入有效邮箱',
    'passwordError': '至少 8 位，并同时包含字母和数字',
    'registerAction': '注册并开始使用',
    'loginAction': '登录',
    'goLogin': '已有账号？去登录',
    'goRegister': '还没有账号？立即注册',
    'changeAvatar': '更换头像',
    'avatarRule': '统一裁剪为 1:1，输出 512 × 512 JPEG，最大 1 MB',
    'takePhoto': '拍摄照片',
    'choosePhoto': '从相册选择',
    'systemAvatar': '系统头像',
    'cropAvatar': '裁剪头像',
    'invalidImage': '无法读取这张图片',
    'avatarTooLarge': '处理后的头像超过 1 MB',
    'networkUnavailable': '网络连接不可用',
    'profile': '我的',
    'home': '首页',
    'discover': '发现',
    'create': '发布',
    'messages': '消息',
    'safetyCenter': '安全中心',
    'safetySubtitle': '联系人 · 定时确认 · 安全会面',
    'activitiesCommunity': '活动与社区',
    'myEvents': '我的活动',
    'trustReviews': '信誉与评价',
    'blocksReports': '黑名单与举报',
    'helpRules': '帮助与社区规范',
    'privacyAccount': '隐私与账号管理',
    'privacySubtitle': '导出、注销与权限',
    'logout': '退出登录',
    'language': '语言',
    'languageTitle': '界面语言',
    'trust': '信誉',
    'joined': '参加',
    'organized': '组织',
    'attendance': '守约',
    'noAvatars': '暂无可用系统头像',
  },
  'en': {
    'appName': 'Dazi',
    'createAccount': 'Create your Dazi account',
    'welcomeBack': 'Welcome back',
    'registerSubtitle': 'Meet new people, starting with an avatar you like',
    'loginSubtitle': 'Sign in to keep discovering nearby activities',
    'chooseAvatar': 'Choose a system avatar',
    'nickname': 'Nickname',
    'email': 'Email',
    'password': 'Password',
    'nicknameError': 'Nickname must be at least 2 characters',
    'emailError': 'Enter a valid email address',
    'passwordError': 'Use 8+ characters with letters and numbers',
    'registerAction': 'Create account',
    'loginAction': 'Sign in',
    'goLogin': 'Already have an account? Sign in',
    'goRegister': 'New here? Create an account',
    'changeAvatar': 'Change avatar',
    'avatarRule': 'Cropped to 1:1, exported as 512 × 512 JPEG, max 1 MB',
    'takePhoto': 'Take photo',
    'choosePhoto': 'Choose from library',
    'systemAvatar': 'System avatars',
    'cropAvatar': 'Crop avatar',
    'invalidImage': 'This image could not be read',
    'avatarTooLarge': 'The processed avatar exceeds 1 MB',
    'networkUnavailable': 'Network connection unavailable',
    'profile': 'Profile',
    'home': 'Home',
    'discover': 'Discover',
    'create': 'Create',
    'messages': 'Messages',
    'safetyCenter': 'Safety center',
    'safetySubtitle': 'Contacts · Check-ins · Safe meetup',
    'activitiesCommunity': 'Activities & community',
    'myEvents': 'My activities',
    'trustReviews': 'Trust & reviews',
    'blocksReports': 'Blocks & reports',
    'helpRules': 'Help & community rules',
    'privacyAccount': 'Privacy & account',
    'privacySubtitle': 'Export, delete & permissions',
    'logout': 'Sign out',
    'language': 'Language',
    'languageTitle': 'App language',
    'trust': 'Trust',
    'joined': 'Joined',
    'organized': 'Hosted',
    'attendance': 'Reliability',
    'noAvatars': 'No system avatars available',
  },
  'ko': {
    'appName': '다지',
    'createAccount': '다지 계정 만들기',
    'welcomeBack': '다시 오신 것을 환영해요',
    'registerSubtitle': '마음에 드는 아바타로 새로운 만남을 시작하세요',
    'loginSubtitle': '로그인하고 주변 모임을 계속 찾아보세요',
    'chooseAvatar': '시스템 아바타 선택',
    'nickname': '닉네임',
    'email': '이메일',
    'password': '비밀번호',
    'nicknameError': '닉네임은 2자 이상이어야 합니다',
    'emailError': '올바른 이메일을 입력하세요',
    'passwordError': '영문과 숫자를 포함해 8자 이상 입력하세요',
    'registerAction': '가입하고 시작하기',
    'loginAction': '로그인',
    'goLogin': '이미 계정이 있나요? 로그인',
    'goRegister': '처음이신가요? 회원가입',
    'changeAvatar': '아바타 변경',
    'avatarRule': '1:1로 자르고 512 × 512 JPEG, 최대 1 MB로 저장합니다',
    'takePhoto': '사진 촬영',
    'choosePhoto': '앨범에서 선택',
    'systemAvatar': '시스템 아바타',
    'cropAvatar': '아바타 자르기',
    'invalidImage': '이미지를 읽을 수 없습니다',
    'avatarTooLarge': '처리된 아바타가 1 MB를 초과합니다',
    'networkUnavailable': '네트워크에 연결할 수 없습니다',
    'profile': '내 정보',
    'home': '홈',
    'discover': '둘러보기',
    'create': '만들기',
    'messages': '메시지',
    'safetyCenter': '안전 센터',
    'safetySubtitle': '연락처 · 상태 확인 · 안전한 만남',
    'activitiesCommunity': '모임 및 커뮤니티',
    'myEvents': '내 모임',
    'trustReviews': '신뢰도 및 후기',
    'blocksReports': '차단 및 신고',
    'helpRules': '도움말 및 커뮤니티 규칙',
    'privacyAccount': '개인정보 및 계정',
    'privacySubtitle': '내보내기, 탈퇴 및 권한',
    'logout': '로그아웃',
    'language': '언어',
    'languageTitle': '화면 언어',
    'trust': '신뢰도',
    'joined': '참여',
    'organized': '주최',
    'attendance': '약속 준수',
    'noAvatars': '사용 가능한 시스템 아바타가 없습니다',
  },
};
