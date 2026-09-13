import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Dart key (snake_case, matches the platform channel argument) -> the
  // CFBundleAlternateIcons name in Info.plist. "original_light" is the
  // primary bundle icon itself (AppIcon.appiconset), which iOS always
  // means by a nil alternate name — it has no entry here. Keep this map
  // in step with `AppIcon` in lib/core/platform/app_icon.dart.
  private static let alternateIconNames: [String: String] = [
    "original_dark": "OriginalDark",
    "booklines_light": "BooklinesLight",
    "booklines_dark": "BooklinesDark",
    "lavender": "Lavender",
    "midnight": "Midnight",
    "mint": "Mint",
    "raspberry": "Raspberry",
    "rose": "Rose",
    "sunflower": "Sunflower",
    "sunset_light": "SunsetLight",
    "sunset_dark": "SunsetDark",
    "clouds_light": "CloudsLight",
    "clouds_dark": "CloudsDark",
    "triangles_light": "TrianglesLight",
    "triangles_dark": "TrianglesDark",
  ]

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The launcher icon lives entirely on the OS side — nothing here
    // persists a preference of its own; `alternateIconName` is what iOS
    // already remembers across launches.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppIconChannel")
    let channel = FlutterMethodChannel(
      name: "cactus/app_icon",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "currentIcon":
        let current = UIApplication.shared.alternateIconName
        let key = Self.alternateIconNames.first { $0.value == current }?.key
        result(key ?? "original_light")
      case "setIcon":
        guard let args = call.arguments as? [String: Any],
          let name = args["name"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "Missing icon name", details: nil))
          return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: "Alternate icons unsupported", details: nil))
          return
        }
        // nil for "original_light" (the primary bundle icon) — every
        // other key must resolve to a known alternate.
        let iconName: String?
        if name == "original_light" {
          iconName = nil
        } else if let mapped = Self.alternateIconNames[name] {
          iconName = mapped
        } else {
          result(FlutterError(code: "bad_args", message: "Unknown icon name: \(name)", details: nil))
          return
        }
        UIApplication.shared.setAlternateIconName(iconName) { error in
          if let error = error {
            result(FlutterError(code: "set_icon_failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
