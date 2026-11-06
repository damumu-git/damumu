import 'package:flutter/material.dart';

import 'l10n.dart';

final _hangul = RegExp(r'[\u1100-\u11ff\u3130-\u318f\uac00-\ud7a3]');
final _han = RegExp(r'[\u3400-\u9fff]');
final _latin = RegExp(r'[a-zA-Z]');

bool expiredActivity(DateTime? endsAt, DateTime now) {
  if (endsAt == null) return false;
  const koreaOffset = Duration(hours: 9);
  final koreaNow = now.toUtc().add(koreaOffset);
  final midnight = DateTime.utc(
    koreaNow.year,
    koreaNow.month,
    koreaNow.day,
  ).subtract(koreaOffset);
  return endsAt.isBefore(midnight);
}

String activityTime(BuildContext context, DateTime date) {
  final format = MaterialLocalizations.of(context);
  final localDate = date.toLocal();
  final time = format.formatTimeOfDay(TimeOfDay.fromDateTime(localDate));
  return '${format.formatMediumDate(localDate)} · $time';
}

String activityPrice(BuildContext context, int amount) {
  if (amount == 0) return context.tr('activityFree');
  return context
      .tr('activityEstimatedCost')
      .replaceFirst('{amount}', '$amount');
}

String activityText(
  BuildContext context,
  Map<String, dynamic>? item,
  String field,
  String original,
) {
  if (item?['translations'] is! Map || original.trim().isEmpty) return original;
  final language = Localizations.localeOf(context).languageCode;
  final translations = item!['translations'] as Map;
  if (field == 'category') {
    final custom = item['custom_subcategory'] as String?;
    if (custom != null && custom.trim().isNotEmpty) {
      return _translated(context, translations, language, field, custom);
    }
    final names = item['category_names'];
    final name = names is Map ? names[language] : null;
    if (name is String && name.trim().isNotEmpty) return name;
    return context.tr('activityCategoryUnavailable');
  }
  return _translated(context, translations, language, field, original);
}

String _translated(
  BuildContext context,
  Map translations,
  String language,
  String field,
  String original,
) {
  final entry = translations[language];
  final translated = entry is Map ? entry[field] : null;
  if (translated is String && translated.trim().isNotEmpty) return translated;
  final source = _hangul.hasMatch(original)
      ? 'ko'
      : _han.hasMatch(original)
      ? 'zh'
      : _latin.hasMatch(original)
      ? 'en'
      : null;
  return source == null || source == language
      ? original
      : context.tr('activityTranslationUnavailable');
}
