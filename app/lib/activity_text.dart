import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';

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
      .replaceFirst('{amount}', formatThousands(amount));
}

String formatThousands(int amount) => amount.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

int? parseFormattedAmount(String value) =>
    int.tryParse(value.replaceAll(',', '').trim());

class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    digits = digits.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
    final amount = int.tryParse(digits);
    if (amount == null) return oldValue;
    final formatted = formatThousands(amount);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
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
      return _translated(translations, language, field, custom);
    }
    final names = item['category_names'];
    final name = names is Map ? names[language] : null;
    if (name is String && name.trim().isNotEmpty) return name;
    return original;
  }
  return _translated(translations, language, field, original);
}

String _translated(
  Map translations,
  String language,
  String field,
  String original,
) {
  final entry = translations[language];
  final translated = entry is Map ? entry[field] : null;
  if (translated is String && translated.trim().isNotEmpty) return translated;
  return original;
}
