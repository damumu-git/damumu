import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';

// Enable only after the release's recipients, countries and legal basis have
// been verified and the complete notices are published. OS permission is separate.
const externalProcessingDisclosureApproved = bool.fromEnvironment(
  'EXTERNAL_PROCESSING_DISCLOSURE_APPROVED',
  defaultValue: false,
);

Future<bool> externalProcessingAllowed(String feature) async =>
    externalProcessingDisclosureApproved &&
    (await SharedPreferences.getInstance()).getBool(
          'external_${feature}_20261021',
        ) ==
        true;

class ExternalProcessingSettings extends StatefulWidget {
  const ExternalProcessingSettings({super.key, this.onPushChanged});
  final Future<void> Function(bool)? onPushChanged;
  @override
  State<ExternalProcessingSettings> createState() =>
      _ExternalProcessingSettingsState();
}

class _ExternalProcessingSettingsState
    extends State<ExternalProcessingSettings> {
  bool _push = false;
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final push = await externalProcessingAllowed('push');
    final geocoding = await externalProcessingAllowed('geocoding');
    if (mounted) {
      setState(() {
        _push = push;
        _geocoding = geocoding;
      });
    }
  }

  Future<void> _set(String feature, bool value) async {
    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('externalProcessingTitle')),
          content: Text(
            context.tr(
              feature == 'push'
                  ? 'pushProcessingNotice'
                  : 'geocodingProcessingNotice',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('confirm')),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    await (await SharedPreferences.getInstance()).setBool(
      'external_${feature}_20261021',
      value,
    );
    if (feature == 'push') {
      await widget.onPushChanged?.call(value);
    }
    if (mounted) {
      setState(() {
        if (feature == 'push') {
          _push = value;
        } else {
          _geocoding = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (!externalProcessingDisclosureApproved)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('externalProcessingUnavailable')),
        ),
      SwitchListTile(
        title: Text(context.tr('optionalSystemPush')),
        value: _push,
        onChanged: externalProcessingDisclosureApproved
            ? (value) => _set('push', value)
            : null,
      ),
      SwitchListTile(
        title: Text(context.tr('optionalGeocoding')),
        value: _geocoding,
        onChanged: externalProcessingDisclosureApproved
            ? (value) => _set('geocoding', value)
            : null,
      ),
    ],
  );
}
