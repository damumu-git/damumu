import 'package:flutter/material.dart';

import 'l10n.dart';

class MemberLevelGuideButton extends StatelessWidget {
  const MemberLevelGuideButton({super.key, this.profileLevel, this.foreground});

  final int? profileLevel;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MemberLevelGuide(profileLevel: profileLevel),
    ),
    child: Text(context.tr('memberLevelGuide')),
  );
}

class _MemberLevelGuide extends StatelessWidget {
  const _MemberLevelGuide({this.profileLevel});

  final int? profileLevel;

  static const limits = [
    (rank: 1, open: 1, recent: 2, recurring: null),
    (rank: 2, open: 2, recent: 6, recurring: null),
    (rank: 3, open: 3, recent: 10, recurring: 4),
    (rank: 4, open: 10, recent: 30, recurring: 12),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        context.tr('memberLevelGuide'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [
                  for (final level in limits)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  context
                                      .tr('memberLevelGuideRank')
                                      .replaceFirst('{rank}', '${level.rank}')
                                      .replaceFirst(
                                        '{name}',
                                        context.tr('memberLevel${level.rank}'),
                                      ),
                                  style: theme.textTheme.titleMedium,
                                ),
                                if (level.rank == profileLevel)
                                  Text(
                                    context.tr('memberLevelGuideProfileRank'),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr(
                                'memberLevelGuideCondition${level.rank}',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context
                                  .tr('memberLevelGuideQuota')
                                  .replaceFirst('{open}', '${level.open}')
                                  .replaceFirst('{recent}', '${level.recent}'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (level.recurring case final int occurrences) ...[
                              const SizedBox(height: 4),
                              Text(
                                context
                                    .tr('memberLevelGuideRecurring')
                                    .replaceFirst('{count}', '$occurrences'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      context.tr('memberLevelGuideCriteria'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (final key in [
                    'memberLevelGuideSuccessful',
                    'memberLevelGuideReputation',
                    'memberLevelGuideCancellation',
                    'memberLevelGuideVerification',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(context.tr(key)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
