import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'l10n.dart';

/// A local form only: dismissal never creates an account or accepts consent.
class SocialRegistrationDialog extends StatefulWidget {
  const SocialRegistrationDialog({super.key});

  @override
  State<SocialRegistrationDialog> createState() =>
      _SocialRegistrationDialogState();
}

class _SocialRegistrationDialogState extends State<SocialRegistrationDialog> {
  final _form = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  bool _age = false;
  bool _notice = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.tr('socialCompleteProfile')),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('socialSeparateAccount')),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nickname,
              maxLength: 30,
              decoration: InputDecoration(labelText: context.tr('nickname')),
              validator: (value) => (value?.trim().length ?? 0) < 2
                  ? context.tr('nicknameError')
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _age,
              onChanged: (value) => setState(() => _age = value ?? false),
              title: Text(context.tr('minimumAgeConfirmation')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _notice,
              onChanged: (value) => setState(() => _notice = value ?? false),
              title: Text(context.tr('privacyNoticeAcknowledgement')),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? 'https://www.damumu.com/privacy-ko.html'
                      : 'https://www.damumu.com/privacy.html',
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(context.tr('readPrivacyNotice')),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.tr('cancel')),
      ),
      FilledButton(
        onPressed: !_age || !_notice
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _nickname.text.trim());
                }
              },
        child: Text(context.tr('registerAction')),
      ),
    ],
  );
}
