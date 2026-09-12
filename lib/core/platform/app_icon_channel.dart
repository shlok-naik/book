import 'package:flutter/services.dart';

import 'app_icon.dart';

/// The one seam that talks to native code about the launcher icon —
/// `UIApplication.setAlternateIconName` on iOS, activity-alias toggling
/// on Android (see `MainActivity.kt` and `AppDelegate.swift`). Nothing
/// above [AppIconController] should touch this channel directly.
class AppIconChannel {
  const AppIconChannel();

  static const _channel = MethodChannel('cactus/app_icon');

  /// The icon the OS is actually showing right now.
  Future<AppIcon> current() async {
    final name = await _channel.invokeMethod<String>('currentIcon');
    return AppIconNaming.fromWireName(name);
  }

  /// Switches the launcher icon. On iOS this raises the system's own
  /// "Change to this icon?" confirmation — [invokeMethod] does not
  /// resolve until the reader has answered it.
  Future<void> set(AppIcon icon) {
    return _channel.invokeMethod<void>('setIcon', {'name': icon.wireName});
  }
}
