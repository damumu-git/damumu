import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';

enum AppPermission { camera, photos, notifications, location }

enum PermissionOutcome {
  granted,
  denied,
  settings,
  selectedOnly,
  unsupported,
  failed,
}

class AppPermissions {
  static const channel = MethodChannel('com.damumu.damu/permissions');
  static String key(AppPermission permission) =>
      'permission_choice_${permission.name}_v1';
  static Future<bool?> choice(AppPermission permission) async =>
      (await SharedPreferences.getInstance()).getBool(key(permission));
  static Future<void> decline(AppPermission permission) async {
    await (await SharedPreferences.getInstance()).setBool(
      key(permission),
      false,
    );
  }

  static Future<PermissionOutcome> request(AppPermission permission) async {
    PermissionOutcome outcome;
    try {
      if (permission == AppPermission.photos) {
        // No full-library access: the system picker grants only selected files.
        outcome = PermissionOutcome.selectedOnly;
      } else if (kIsWeb ||
          (defaultTargetPlatform != TargetPlatform.android &&
              defaultTargetPlatform != TargetPlatform.iOS)) {
        outcome = PermissionOutcome.unsupported;
      } else if (permission == AppPermission.location) {
        var status = await Geolocator.checkPermission();
        if (status == LocationPermission.denied) {
          status = await Geolocator.requestPermission();
        }
        outcome = switch (status) {
          LocationPermission.always ||
          LocationPermission.whileInUse => PermissionOutcome.granted,
          LocationPermission.deniedForever => PermissionOutcome.settings,
          _ => PermissionOutcome.denied,
        };
      } else {
        final result = await channel.invokeMethod<String>(
          'request',
          permission.name,
        );
        outcome = switch (result) {
          'granted' => PermissionOutcome.granted,
          'settings' => PermissionOutcome.settings,
          'denied' => PermissionOutcome.denied,
          _ => PermissionOutcome.failed,
        };
      }
    } catch (_) {
      outcome = PermissionOutcome.failed;
    }
    await (await SharedPreferences.getInstance()).setBool(
      key(permission),
      outcome == PermissionOutcome.granted ||
          outcome == PermissionOutcome.selectedOnly,
    );
    return outcome;
  }

  // Reconsider only after an explicit feature action, never on page loading.
  static Future<bool> ensure(
    BuildContext context,
    AppPermission permission,
  ) async {
    if (await choice(permission) == true) return true;
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('intro_${permission.name}_title')),
        content: Text(context.tr('intro_${permission.name}_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('permissionDecline')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('permissionAgree')),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    // Browsers grant access at the actual picker/GPS action rather than through
    // the native mobile permission channel. Preserve those existing flows.
    if (kIsWeb &&
        (permission == AppPermission.camera ||
            permission == AppPermission.location)) {
      await (await SharedPreferences.getInstance()).setBool(
        key(permission),
        true,
      );
      return true;
    }
    final result = await request(permission);
    if (result == PermissionOutcome.settings && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('permissionSettingsRequired')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Geolocator.openAppSettings();
              },
              child: Text(context.tr('permissionOpenSettings')),
            ),
          ],
        ),
      );
    } else if (permission == AppPermission.location &&
        context.mounted &&
        result != PermissionOutcome.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              result == PermissionOutcome.denied
                  ? 'locationPermissionDenied'
                  : 'locationFailed',
            ),
          ),
        ),
      );
    }
    return result == PermissionOutcome.granted ||
        result == PermissionOutcome.selectedOnly;
  }

  static Future<bool> ensureImage(BuildContext context, ImageSource source) =>
      ensure(
        context,
        source == ImageSource.camera
            ? AppPermission.camera
            : AppPermission.photos,
      );
}
