import 'package:flutter/material.dart';

import 'event_service.dart';
import 'feedback_model.dart';
import 'l10n.dart';

String feedbackTagLabel(BuildContext context, String code) =>
    context.tr('feedbackTag_$code');

class FeedbackActionGrid extends StatefulWidget {
  const FeedbackActionGrid({
    required this.token,
    required this.eventId,
    required this.targetType,
    this.targetUserId,
    this.initialEligibility,
    this.onPublishSimilar,
    this.onLikeSubmitted,
    super.key,
  });

  final String token;
  final String eventId;
  final String targetType;
  final String? targetUserId;
  final FeedbackEligibilityData? initialEligibility;
  final VoidCallback? onPublishSimilar;
  final VoidCallback? onLikeSubmitted;

  @override
  State<FeedbackActionGrid> createState() => _FeedbackActionGridState();
}

class _FeedbackActionGridState extends State<FeedbackActionGrid> {
  FeedbackEligibilityData? _eligibility;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _eligibility = widget.initialEligibility;
    if (_eligibility == null) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final value = await EventService.feedbackEligibility(
        widget.token,
        widget.eventId,
        widget.targetType,
        targetUserId: widget.targetUserId,
      );
      if (mounted) setState(() => _eligibility = value);
    } catch (_) {
      // The API is authoritative. Ineligible or unavailable actions stay hidden.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (widget.onPublishSimilar != null)
        FeedbackActionCard(
          icon: Icons.copy_outlined,
          label: context.tr('publishSimilar'),
          onTap: widget.onPublishSimilar,
        ),
      if (_eligibility?.eligible == true)
        FeedbackActionCard(
          icon: _eligibility?.likeTag == null
              ? Icons.favorite_border
              : Icons.favorite,
          label: _eligibility?.likeTag == null
              ? context.tr('like')
              : context.tr('liked'),
          color: Colors.pink.shade600,
          onTap: () => _submit('like'),
        ),
      if (_eligibility?.eligible == true)
        FeedbackActionCard(
          icon: Icons.flag_outlined,
          label: _eligibility?.reportTag == null
              ? context.tr('report')
              : context.tr('reported'),
          color: Colors.orange.shade800,
          onTap: _eligibility?.reportTag == null
              ? () => _submit('report')
              : null,
        ),
      if (_loading)
        const SizedBox(
          width: 104,
          height: 104,
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(spacing: 12, runSpacing: 12, children: actions),
    );
  }

  Future<void> _submit(String feedbackType) async {
    final tags = switch ((widget.targetType, feedbackType)) {
      ('activity', 'like') => activityLikeTags,
      ('activity', 'report') => activityReportTags,
      ('user', 'like') => userLikeTags,
      _ => userReportTags,
    };
    final result = await showDialog<({String tag, String? description})>(
      context: context,
      builder: (_) => FeedbackTagDialog(
        feedbackType: feedbackType,
        tags: tags,
        selectedTag: feedbackType == 'like'
            ? _eligibility?.likeTag
            : _eligibility?.reportTag,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await EventService.submitFeedback(
        widget.token,
        eventId: widget.eventId,
        targetType: widget.targetType,
        targetUserId: widget.targetUserId,
        feedbackType: feedbackType,
        tagCode: result.tag,
        description: result.description,
      );
      if (!mounted) return;
      setState(() {
        _eligibility = feedbackType == 'like'
            ? _eligibility!.copyWith(likeTag: result.tag)
            : _eligibility!.copyWith(reportTag: result.tag);
      });
      if (feedbackType == 'like') widget.onLikeSubmitted?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('feedbackSubmitted'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('feedbackFailed'))));
      }
    }
  }
}

class FeedbackActionCard extends StatelessWidget {
  const FeedbackActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    height: 104,
    child: Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: onTap == null ? Colors.grey : color, size: 30),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FeedbackTagDialog extends StatefulWidget {
  const FeedbackTagDialog({
    required this.feedbackType,
    required this.tags,
    this.selectedTag,
    super.key,
  });

  final String feedbackType;
  final List<String> tags;
  final String? selectedTag;

  @override
  State<FeedbackTagDialog> createState() => _FeedbackTagDialogState();
}

class _FeedbackTagDialogState extends State<FeedbackTagDialog> {
  String? _tag;
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tag = widget.selectedTag;
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.feedbackType == 'like'
          ? context.tr('chooseLikeTag')
          : context.tr('chooseReportTag'),
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags
                .map(
                  (tag) => ChoiceChip(
                    label: Text(feedbackTagLabel(context, tag)),
                    selected: _tag == tag,
                    onSelected: (_) => setState(() => _tag = tag),
                  ),
                )
                .toList(),
          ),
          if (widget.feedbackType == 'report') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: context.tr('reportDescription'),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: _tag == null
            ? null
            : () => Navigator.pop(context, (
                tag: _tag!,
                description: _description.text.trim().isEmpty
                    ? null
                    : _description.text.trim(),
              )),
        child: Text(context.tr('submitFeedback')),
      ),
    ],
  );
}
