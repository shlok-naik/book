package com.shloknaik.cactus

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Switches the launcher icon by enabling exactly one of sixteen
/// components — this activity itself (for "original_light") or one of
/// the fifteen `.MainActivity<Style><Mode>` aliases in
/// AndroidManifest.xml — and disabling the rest. Every alias points
/// back at this same activity, so the running app is never affected,
/// only which icon and label the launcher shows.
///
/// "original_light" is this real activity rather than a sixteenth alias
/// specifically because `flutter run`/`aapt` only recognize a real
/// `<activity>`'s own intent-filter as a launch target, not an alias's —
/// see the manifest comment on MainActivity's intent-filter. Disabling
/// this activity's own component when switching to a different icon is
/// safe: an alias's ability to launch its targetActivity does not
/// depend on the target's own enabled flag, only the alias's.
///
/// Keep [componentSuffixes] in step with `AppIcon` in
/// lib/core/platform/app_icon.dart.
class MainActivity : FlutterActivity() {
    private val channelName = "cactus/app_icon"

    /// Dart key (snake_case, matches the platform channel argument) ->
    /// manifest component suffix. `null` means "this activity itself"
    /// rather than `.MainActivity<suffix>`.
    private val componentSuffixes = mapOf(
        "original_light" to null,
        "original_dark" to "OriginalDark",
        "booklines_light" to "BooklinesLight",
        "booklines_dark" to "BooklinesDark",
        "lavender" to "Lavender",
        "midnight" to "Midnight",
        "mint" to "Mint",
        "raspberry" to "Raspberry",
        "rose" to "Rose",
        "sunflower" to "Sunflower",
        "sunset_light" to "SunsetLight",
        "sunset_dark" to "SunsetDark",
        "clouds_light" to "CloudsLight",
        "clouds_dark" to "CloudsDark",
        "triangles_light" to "TrianglesLight",
        "triangles_dark" to "TrianglesDark",
    )

    private fun componentFor(suffix: String?): ComponentName =
        if (suffix == null) {
            ComponentName(applicationContext, MainActivity::class.java)
        } else {
            ComponentName(applicationContext, "$packageName.MainActivity$suffix")
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "currentIcon" -> result.success(currentIconKey())
                    "setIcon" -> {
                        val name = call.argument<String>("name")
                        if (!componentSuffixes.containsKey(name)) {
                            result.error("bad_args", "Unknown icon name: $name", null)
                        } else {
                            // Reply before setIcon's last step, which may
                            // kill this process as a deliberate side
                            // effect (see setIcon's comment) — Dart must
                            // already have its answer by then.
                            result.success(null)
                            setIcon(name!!)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun currentIconKey(): String {
        for ((key, suffix) in componentSuffixes) {
            if (suffix == null) continue // checked last, as the fallback default below
            val state = packageManager.getComponentEnabledSetting(componentFor(suffix))
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return key
        }
        // Nothing explicitly enabled yet (a fresh install before this
        // channel has ever set anything), or MainActivity's own default
        // (unset) enabled-state — both mean original/light, since that
        // is the manifest's own default launcher entry.
        return "original_light"
    }

    private fun setIcon(name: String) {
        val toEnable = componentFor(componentSuffixes.getValue(name))

        // Enable the target first, then disable every other component —
        // never a moment with none enabled, which would leave the app
        // with no launcher icon at all until PackageManager settles.
        // DONT_KILL_APP on these two steps only gets every component's
        // state correct without disrupting the app we're currently
        // running in partway through.
        packageManager.setComponentEnabledSetting(
            toEnable,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((otherName, otherSuffix) in componentSuffixes) {
            if (otherName == name) continue
            packageManager.setComponentEnabledSetting(
                componentFor(otherSuffix),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }

        // Re-apply the same enabled state to the target once more, this
        // time WITHOUT DONT_KILL_APP, now that every component already
        // has its correct final state. This is the step that actually
        // matters for the launcher: omitting DONT_KILL_APP is what makes
        // the OS broadcast the package-changed signal launchers (Pixel
        // Launcher included) rely on to re-fetch an app's icon — using
        // DONT_KILL_APP everywhere (as this used to) silently suppressed
        // that broadcast, leaving the home screen showing a stale or
        // placeholder icon after every switch even though the correct
        // component was enabled underneath. The process may die here as
        // a result, which is fine: the reader was already told the app
        // would restart, and `result.success` already ran.
        packageManager.setComponentEnabledSetting(
            toEnable,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            0,
        )
    }
}
