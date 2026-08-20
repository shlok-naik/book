import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the .env-configured secrets — read through here
/// instead of touching `dotenv.env` directly elsewhere.
abstract final class Env {
  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');
  static String get googleBooksApiKey => _require('GOOGLE_BOOKS_API_KEY');
  static String get revenueCatApiKey => _require('REVENUECAT_API_KEY');
  static String get groqApiKey => _require('GROQ_API_KEY');

  /// The Google Books volumes endpoint also serves anonymous requests
  /// (at a lower quota), so a missing key degrades to keyless search
  /// instead of taking the whole search flow down. Returns null when the
  /// key — or the .env file itself — is absent.
  static String? get googleBooksApiKeyOrNull {
    try {
      return googleBooksApiKey;
    } on Object {
      return null;
    }
  }

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing "$key" in .env — copy .env.example to .env and fill it in.',
      );
    }
    return value;
  }
}
