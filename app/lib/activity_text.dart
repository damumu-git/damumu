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

String activityMajorCategory(BuildContext context, Map<String, dynamic>? item) {
  if (item == null ||
      item['cover_category_code'] == item['cover_subcategory_code']) {
    return '';
  }
  final suffix = switch (Localizations.localeOf(context).languageCode) {
    'en' => '_en_us',
    'ko' => '_ko_kr',
    _ => '',
  };
  final localized = (item['major_category_name$suffix'] as String?)?.trim();
  return localized != null && localized.isNotEmpty
      ? localized
      : (item['major_category_name'] as String?)?.trim() ?? '';
}

class ActivityListTags extends StatelessWidget {
  const ActivityListTags({
    required this.data,
    required this.category,
    required this.owned,
    super.key,
  });

  final Map<String, dynamic>? data;
  final String category;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final major = activityMajorCategory(context, data);
    final minor = activityText(context, data, 'category', category);
    if (major.isEmpty && minor.isEmpty && !owned) {
      return const SizedBox.shrink();
    }
    Widget tag(
      String label,
      Color ink,
      Color fill, {
      Color? border,
      double radius = 12,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        border: border == null ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (major.isNotEmpty)
          tag(major, const Color(0xff293b85), const Color(0xffedf0ff)),
        if (minor.isNotEmpty)
          tag(
            minor,
            const Color(0xff404b5c),
            Colors.white,
            border: const Color(0xffd6ddea),
          ),
        if (owned)
          tag(
            context.tr('eventOwned'),
            const Color(0xff165339),
            const Color(0xffe7f6ed),
            radius: 4,
          ),
      ],
    );
  }
}

String activityRegionSearchText(Map<String, dynamic>? item) {
  if (item == null) return '';
  const keys = [
    'city_name',
    'city_name_ko_kr',
    'city_name_en_us',
    'municipality_name',
    'municipality_name_ko_kr',
    'municipality_name_en_us',
    'district_name',
    'district_name_ko_kr',
    'district_name_en_us',
  ];
  return keys
      .map((key) => item[key]?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' ')
      .toLowerCase();
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
