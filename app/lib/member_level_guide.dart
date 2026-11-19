import 'package:flutter/material.dart';

import 'l10n.dart';

class MemberMedal extends StatelessWidget {
  const MemberMedal({super.key, required this.rank, required this.size});

  final int rank;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/damumu-brand/level-$rank.webp',
    height: size,
    width: size,
    excludeFromSemantics: true,
  );
}

class MemberLevelBadge extends StatelessWidget {
  const MemberLevelBadge(this.level, {super.key});

  final Object? level;

  @override
  Widget build(BuildContext context) {
    final rank = (level as num?)?.toInt();
    if (rank == null || rank < 1 || rank > 4) return const SizedBox.shrink();
    const backgrounds = [
      Color(0xFFE9EDF5),
      Color(0xFFDAF1E9),
      Color(0xFFE9E6FF),
      Color(0xFFFCECCF),
    ];
    const foregrounds = [
      Color(0xFF3E506B),
      Color(0xFF155B49),
      Color(0xFF4D3798),
      Color(0xFF77480B),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgrounds[rank - 1],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          context.tr('memberLevel$rank'),
          style: TextStyle(
            color: foregrounds[rank - 1],
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class RankedMemberName extends StatelessWidget {
  const RankedMemberName(
    this.name, {
    super.key,
    this.level,
    this.prefix,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String name;
  final Object? level;
  final String? prefix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final rank = (level as num?)?.toInt();
    return Text.rich(
      TextSpan(
        children: [
          if (prefix != null) TextSpan(text: prefix),
          if (rank != null && rank >= 1 && rank <= 4)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 3),
                child: MemberMedal(rank: rank, size: 16),
              ),
            ),
          TextSpan(text: name),
        ],
      ),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

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

class _MemberLevelGuide extends StatefulWidget {
  const _MemberLevelGuide({this.profileLevel});

  final int? profileLevel;

  @override
  State<_MemberLevelGuide> createState() => _MemberLevelGuideState();
}

class _MemberLevelGuideState extends State<_MemberLevelGuide> {
  static const limits = [
    (open: 2, recent: 4, recurring: null, color: Color(0xffe5f1ff)),
    (open: 3, recent: 6, recurring: null, color: Color(0xffd9f2eb)),
    (open: 5, recent: 10, recurring: 4, color: Color(0xffeae7ff)),
    (open: 10, recent: 30, recurring: 12, color: Color(0xfffff0cf)),
  ];
  late int _selected = (widget.profileLevel ?? 1).clamp(1, limits.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = limits[_selected - 1];
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
                  Image.asset(
                    'assets/damumu-brand/damumu-mark.webp',
                    width: 34,
                    height: 34,
                    semanticLabel: 'DAMUMU',
                  ),
                  const SizedBox(width: 8),
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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var rank = 1; rank <= limits.length; rank++)
                        Expanded(child: _step(context, rank)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                context.tr('memberLevel$_selected'),
                                style: theme.textTheme.titleMedium,
                              ),
                              if (_selected == widget.profileLevel)
                                Text(
                                  context.tr('memberLevelGuideProfileRank'),
                                  style: theme.textTheme.labelMedium,
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr('memberLevelGuideCondition$_selected'),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _quota(
                                  context,
                                  level.open,
                                  'memberLevelGuideOpen',
                                ),
                              ),
                              Expanded(
                                child: _quota(
                                  context,
                                  level.recent,
                                  'memberLevelGuideRecent',
                                ),
                              ),
                            ],
                          ),
                          if (level.recurring case final int occurrences) ...[
                            const SizedBox(height: 10),
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
                  for (final key in [
                    'memberLevelGuideSuccessful',
                    'memberLevelGuideVerification',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 10,
                        left: 4,
                        right: 4,
                      ),
                      child: Text(
                        context.tr(key),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(BuildContext context, int rank) {
    final theme = Theme.of(context);
    final selected = rank == _selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        selected: selected,
        button: true,
        child: Tooltip(
          message: context.tr('memberLevel$rank'),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selected = rank),
            child: Container(
              height:
                  49.0 + rank * 11 + MediaQuery.textScalerOf(context).scale(15),
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: limits[rank - 1].color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                  bottom: Radius.circular(5),
                ),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MemberMedal(rank: rank, size: 38),
                  Text(
                    'Lv$rank',
                    style: const TextStyle(
                      color: Color(0xff354365),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quota(BuildContext context, int count, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$count', style: Theme.of(context).textTheme.titleLarge),
      Text(context.tr(label), style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
