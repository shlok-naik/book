import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// A human name for this device — "Google Pixel 8", "iPhone 15 Pro" — shown
/// when a reader chooses between two libraries. Deliberately the model, not
/// the owner-set name ("Sam's iPhone"): iOS only hands that out with a
/// special entitlement, and it's more personal than this needs.
abstract final class DeviceName {
  static Future<String?> current() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final brand = android.brand.isEmpty
            ? ''
            : '${android.brand[0].toUpperCase()}${android.brand.substring(1)} ';
        final model = android.model.startsWith(android.brand)
            ? android.model
            : '$brand${android.model}';
        return _clean(model);
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return _clean(ios.modelName.isNotEmpty ? ios.modelName : ios.model);
      }
    } on Object {
      return null;
    }
    return null;
  }

  static String? _clean(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > 80 ? trimmed.substring(0, 80) : trimmed;
  }
}
