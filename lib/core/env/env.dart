import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the app's configuration — read through here instead
/// of touching `dotenv.env` directly anywhere else.
///
/// Two sources, in order:
///
/// 1. **Compile-time `--dart-define`s.** How release builds should be
///    configured: the values are baked into the binary by the build,
///    so nothing has to be shipped as a readable asset and CI can inject
///    them from its own secret store without a file ever existing on
///    disk.
/// 2. **A local `.env` file**, for development convenience — and *only*
///    in debug and profile builds. It is bundled as a Flutter asset (see
///    `pubspec.yaml`), so anything in it is readable by anyone who
///    unzips a build; a release build therefore refuses to read it at
///    all. That is a deliberate trade: a release missing a
///    `--dart-define` fails loudly at startup rather than quietly
///    shipping with configuration baked into a readable file.
///
/// Neither source is a place for a *secret*: everything here reaches the
/// device, so everything here is public by construction. That is fine
/// for the values below — the Supabase publishable key is designed to be
/// public and is backed by row level security, and the RevenueCat key is
/// its public SDK key. It is exactly why the model provider's API key is
/// *not* here any more: it is a Supabase project secret, held by the
/// `parse-command` edge function, and the app talks to that function
/// instead (see `EdgeFunctionCommandParser`).
abstract final class Env {
  // `String.fromEnvironment` must be const-initialised to be read at
  // compile time — a non-const call always returns the empty string.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _googleBooksApiKey = String.fromEnvironment(
    'GOOGLE_BOOKS_API_KEY',
  );
  static const _revenueCatApiKey = String.fromEnvironment('REVENUECAT_API_KEY');

  static String get supabaseUrl => _require('SUPABASE_URL', _supabaseUrl);

  /// Supabase's publishable ("anon") key. Public by design — it grants
  /// nothing on its own; the row level security policies in
  /// `supabase/migrations/` are what actually gate every table.
  static String get supabaseAnonKey =>
      _require('SUPABASE_ANON_KEY', _supabaseAnonKey);

  static String get googleBooksApiKey =>
      _require('GOOGLE_BOOKS_API_KEY', _googleBooksApiKey);

  /// RevenueCat's *public* SDK key, not a secret API key.
  static String get revenueCatApiKey =>
      _require('REVENUECAT_API_KEY', _revenueCatApiKey);

  /// The Google Books volumes endpoint also serves anonymous requests
  /// (at a lower quota), so a missing key degrades to keyless search
  /// instead of taking the whole search flow down. Returns null when the
  /// key — or the `.env` file itself — is absent.
  static String? get googleBooksApiKeyOrNull =>
      _lookup('GOOGLE_BOOKS_API_KEY', _googleBooksApiKey);

  /// Every key this app needs to start, so a misconfigured build fails
  /// at launch with a list of what is missing rather than at the first
  /// screen that happens to touch one. See [missingKeys].
  static const requiredKeys = <String>[
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'REVENUECAT_API_KEY',
  ];

  /// Which of [requiredKeys] resolved to nothing. Empty on a correctly
  /// configured build. `GOOGLE_BOOKS_API_KEY` is deliberately not in
  /// that list — see [googleBooksApiKeyOrNull].
  static List<String> get missingKeys => [
    for (final key in requiredKeys)
      if (_lookup(key, _compileTimeValues[key] ?? '') == null) key,
  ];

  static const _compileTimeValues = <String, String>{
    'SUPABASE_URL': _supabaseUrl,
    'SUPABASE_ANON_KEY': _supabaseAnonKey,
    'GOOGLE_BOOKS_API_KEY': _googleBooksApiKey,
    'REVENUECAT_API_KEY': _revenueCatApiKey,
  };

  /// Resolves [key], preferring the compile-time [defined] value and
  /// falling back to `.env`. Returns null rather than throwing when
  /// neither has it.
  static String? _lookup(String key, String defined) {
    if (defined.isNotEmpty) return defined;
    // Release builds are --dart-define-only. Enforced here rather than
    // only at the `dotenv.load` call site, so there is exactly one place
    // that decides, and no later caller can reintroduce the fallback.
    if (kReleaseMode) return null;
    try {
      final value = dotenv.env[key];
      return (value == null || value.isEmpty) ? null : value;
    } on Object {
      // `.env` was never loaded — a perfectly normal state for a build
      // configured entirely through --dart-define, and for tests.
      return null;
    }
  }

  static String _require(String key, String defined) {
    final value = _lookup(key, defined);
    if (value != null) return value;
    throw StateError(
      'Missing "$key". Pass it with --dart-define=$key=... , or '
      'copy .env.example to .env and fill it in for local development.',
    );
  }

  /// Whether `.env` is consulted at all. False in release — see the
  /// class doc. Exposed so startup can say which source it is running
  /// on, and so a test can assert the release rule rather than trusting
  /// the comment.
  static bool get isDotEnvFallbackAvailable => !kReleaseMode;
}
