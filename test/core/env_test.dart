import 'package:book/core/env/env.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

/// These run without any `--dart-define`, so every compile-time constant
/// in [Env] is the empty string and the `.env` fallback is what is under
/// test. The precedence rule (define wins over file) cannot be exercised
/// from here — it is a property of the compiler, not of this code — so
/// what is covered is the half that can actually regress: resolution,
/// the missing-key report, and the deliberate difference between a
/// required key and the optional Google Books one.
void main() {
  setUp(dotenv.clean);

  group('a key that is present', () {
    test('resolves from .env', () {
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://example.supabase.co',
      );

      expect(Env.supabaseUrl, 'https://example.supabase.co');
    });
  });

  group('a key that is missing', () {
    test('throws a StateError naming the key and both ways to supply it', () {
      expect(
        () => Env.supabaseUrl,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('SUPABASE_URL'),
              contains('--dart-define'),
              contains('.env'),
            ),
          ),
        ),
      );
    });

    test('is reported by missingKeys rather than only on first use', () {
      expect(Env.missingKeys, containsAll(Env.requiredKeys));
    });

    test('an empty value counts as missing, not as a valid empty string', () {
      dotenv.loadFromString(envString: 'SUPABASE_URL=');

      expect(Env.missingKeys, contains('SUPABASE_URL'));
    });
  });

  group('the Google Books key', () {
    test('is optional — a missing one degrades to keyless search', () {
      expect(Env.googleBooksApiKeyOrNull, isNull);
      expect(Env.missingKeys, isNot(contains('GOOGLE_BOOKS_API_KEY')));
    });

    test('is still returned when it is configured', () {
      dotenv.loadFromString(envString: 'GOOGLE_BOOKS_API_KEY=abc123');

      expect(Env.googleBooksApiKeyOrNull, 'abc123');
    });
  });

  group('the model provider key', () {
    test('is not part of the app config at all any more', () {
      // It lives on the server as a Supabase project secret, held by the
      // `parse-command` edge function. If it ever reappears here, it is
      // shipping inside the app bundle again.
      dotenv.loadFromString(envString: 'GROQ_API_KEY=leaked');

      expect(Env.requiredKeys, isNot(contains('GROQ_API_KEY')));
      expect(Env.missingKeys, isNot(contains('GROQ_API_KEY')));
    });
  });
}
