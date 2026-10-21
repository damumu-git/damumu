DateTime privacyRetentionCutoff(DateTime value) {
  final now = value.toUtc();
  final month = DateTime.utc(now.year, now.month - 3);
  final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
  return DateTime.utc(
    month.year,
    month.month,
    now.day > lastDay ? lastDay : now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );
}
