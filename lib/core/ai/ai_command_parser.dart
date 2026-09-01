import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A failure from an [AiCommandParser] call, already written for a
/// human — the UI shows [message] verbatim. Mirrors
/// `OnboardingException`/`LibraryException`'s shape.
class AiCommandException implements Exception {
  const AiCommandException(this.message, {this.cause});

  final String message;

  /// The underlying error, kept for logs only — never rendered.
  final Object? cause;

  @override
  String toString() =>
      'AiCommandException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Splits a reader's free-form sentence into `LogCommandParser`'s own
/// command grammar — `start`, `update`, `finish`, `rate`, `delete`, plus
/// `remember` and `recommend` — the one thing "cactus pro"'s
/// natural-language mode needs. Everything downstream of that
/// (recognising, validating, applying) stays `LogCommandParser`/
/// `HomePage`'s job. `start`/`update`/`finish` also take an optional
/// trailing date; resolving a phrase like "yesterday" to it needs the
/// reader's own local "today" — the real implementation sends that
/// itself (see `EdgeFunctionCommandParser`); it isn't a parameter here
/// because, unlike [libraryTitles] and [memoryNotes], no caller needs
/// to gather it from anywhere.
///
/// An interface rather than a concrete class so tests can supply fixed
/// extractions without going anywhere near the network.
abstract interface class AiCommandParser {
  /// [libraryTitles] and [memoryNotes] ground the `recommend` command
  /// only — the edge function ignores them for every other line — and
  /// are otherwise harmless to omit; every existing command still works
  /// with both left empty. Kept as plain strings rather than this
  /// feature's own `LibraryBook`/`Memory` types so `core/ai` doesn't
  /// have to depend on either feature (see CLAUDE.md § Feature-first
  /// layout — `core/` is for cross-feature concerns, not the reverse).
  ///
  /// Never returns an empty list in practice: the prompt asks for a
  /// single `"gibberish"` line rather than an empty array when nothing
  /// actionable was found, so that line can run through the exact same
  /// unrecognized-command path as any other instead of the caller
  /// needing a special case for "nothing came back."
  ///
  /// Throws [AiCommandException] — never a partial or best-effort
  /// result — for any failure at all.
  Future<List<String>> extractCommands(
    String message, {
    List<String> libraryTitles = const [],
    List<({String? title, String note})> memoryNotes = const [],
  });
}

/// The real [AiCommandParser]: a call to the `parse-command` Supabase
/// Edge Function (see `supabase/functions/parse-command/index.ts`).
///
/// The model provider's API key lives on the server as a project secret
/// and is never shipped to the client. An earlier version of this class
/// called Groq directly with a key read out of the bundled `.env`, which
/// meant the key was inside every released APK/IPA and extractable from
/// one in minutes. Nothing about the request shape here is secret: the
/// function authenticates the caller from their own Supabase session and
/// rate-limits per reader, so an extracted request is worth no more than
/// the reader's own remaining allowance.
///
/// Holds no resources of its own — the Supabase client is the singleton
/// initialised at startup — so unlike the HTTP-owning clients this is
/// safe to default-construct rather than thread down from the
/// composition root, and there is nothing to dispose.
class EdgeFunctionCommandParser implements AiCommandParser {
  const EdgeFunctionCommandParser({SupabaseClient? client})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Deployed function name — must match the directory under
  /// `supabase/functions/`.
  static const _function = 'parse-command';

  /// Ceiling for the whole round-trip. The function gives up on the
  /// model at 15s, so this only has to cover that plus transport;
  /// past it the reader is better served by an error than a spinner.
  static const _timeout = Duration(seconds: 20);

  /// `YYYY-MM-DD` for the device's own local date — the only thing the
  /// edge function needs to resolve "I started Dune yesterday" to an
  /// absolute date, since it has no other way to know the reader's
  /// timezone or what day it is for them right now.
  static String _todayIso(DateTime now) {
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${pad2(now.month)}-${pad2(now.day)}';
  }

  @override
  Future<List<String>> extractCommands(
    String message, {
    List<String> libraryTitles = const [],
    List<({String? title, String note})> memoryNotes = const [],
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions
          .invoke(
            _function,
            body: {
              'message': message,
              'context': {
                'today': _todayIso(DateTime.now()),
                if (libraryTitles.isNotEmpty) 'library': libraryTitles,
                if (memoryNotes.isNotEmpty)
                  'memories': [
                    for (final memory in memoryNotes)
                      {'title': memory.title, 'note': memory.note},
                  ],
              },
            },
          )
          .timeout(_timeout);
    } on FunctionException catch (error) {
      throw AiCommandException(_messageFor(error), cause: error);
    } on TimeoutException catch (error) {
      throw AiCommandException(
        'That took too long — try again in a moment.',
        cause: error,
      );
    } on Object catch (error) {
      // Covers the offline case and, deliberately, the AssertionError
      // `Supabase.instance` throws when the client was never
      // initialised — that must degrade to a visible message, not a
      // crash (same reasoning as `runSupabase`'s broad fallback).
      throw AiCommandException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    }

    final data = response.data;
    if (data is! Map || data['commands'] is! List) {
      throw AiCommandException(
        "The AI's reply couldn't be read.",
        cause: 'Unexpected payload: $data',
      );
    }

    return [
      for (final line in data['commands'] as List)
        if (line is String && line.trim().isNotEmpty) line.trim(),
    ];
  }

  /// The function answers every failure with a `{ "error": ... }` body
  /// already written for a reader (rate limits, empty input, upstream
  /// trouble), so prefer that over inventing a message here. The
  /// fallback only covers a non-JSON failure — a gateway error page,
  /// say — that never reached the function at all.
  String _messageFor(FunctionException error) {
    final details = error.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return "Couldn't reach the AI right now — try again in a moment.";
  }
}
