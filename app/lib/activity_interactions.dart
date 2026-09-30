import 'package:flutter/material.dart';

import 'auth.dart';
import 'event_service.dart';
import 'l10n.dart';

class AvatarPreviewPage extends StatelessWidget {
  const AvatarPreviewPage({required this.nickname, this.avatarUrl, super.key});
  final String nickname;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final fallback = Center(
      child: Text(
        nickname.trim().isEmpty ? '?' : nickname.characters.first,
        style: const TextStyle(fontSize: 100, color: Colors.white),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(nickname),
        leading: IconButton(
          tooltip: context.tr('closePreview'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: url == null || url.isEmpty
                ? fallback
                : Image.network(
                    absoluteImageUrl(url),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => fallback,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ),
      ),
    );
  }
}

class EventCancellationNotice extends StatelessWidget {
  const EventCancellationNotice({required this.reason, super.key});
  final String reason;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    margin: const EdgeInsets.symmetric(vertical: 12),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('eventCancelled'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${context.tr('cancellationReason')}：$reason'),
        ],
      ),
    ),
  );
}

class CancelEventDialog extends StatefulWidget {
  const CancelEventDialog({
    required this.token,
    required this.eventId,
    super.key,
  });
  final String token;
  final String eventId;

  @override
  State<CancelEventDialog> createState() => _CancelEventDialogState();
}

class _CancelEventDialogState extends State<CancelEventDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await EventService.cancelEvent(
        widget.token,
        widget.eventId,
        _reason.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(_reason.text.trim());
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = context.tr('cancelEventFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AlertDialog(
      title: Text(context.tr('cancelEvent')),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('cancelEventExplanation')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                enabled: !_submitting,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: context.tr('cancellationReason'),
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 500
                    ? context.tr('cancellationReasonRequired')
                    : null,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('keepEvent')),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.tr('confirmCancelEvent')),
        ),
      ],
    ),
  );
}
