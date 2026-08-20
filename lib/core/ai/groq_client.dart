import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env/env.dart';

/// A failure from a [GroqClient] call, already written for a human —
/// the UI shows [message] verbatim. Mirrors `PurchasesException`'s
/// shape.
class GroqException implements Exception {
  const GroqException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'GroqException: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// Thin wrapper over Groq's OpenAI-compatible chat completions endpoint
/// — the only thing "cactus pro"'s natural language mode needs it for:
/// splitting a reader's free-form sentence into [LogCommandParser]'s
/// own command grammar (`start <book>`, `update <book> <page>`,
/// `finish <book>`, `rate <book> <stars>`, `delete <book>`). Everything
/// downstream of that — recognizing, validating, applying — stays
/// exactly `LogCommandParser`/`HomePage`'s job, never this client's.
class GroqClient {
  GroqClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Releases the owned [http.Client]'s connections — call once, from
  /// whichever composition root built this (mirrors
  /// `GoogleBooksApiClient.dispose`).
  void dispose() => _client.close();

  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const _model = 'openai/gpt-oss-120b';

  static const _systemPrompt = '''
You split a reader's natural-language sentence about their reading into a list of structured commands. Only these five commands exist, and every line you output must match one of them exactly (case-insensitive keyword, one command per line, no numbering, no extra words):

start <book title>
update <book title> <page number>
finish <book title>
rate <book title> <stars, 0-5, .5 allowed>
delete <book title>

Rules:
- Extract every distinct action the sentence describes, in the order mentioned.
- Use the book title as written (fix obvious capitalization only).
- If a sentence mentions no page number or star rating, don't guess one — drop that action instead of inventing a number.
- Output ONLY a JSON array of strings, each string one command line. No prose, no markdown fences.
- If nothing recognizable is mentioned, output a single-element array containing exactly the word "gibberish" (lowercase, nothing else): ["gibberish"]''';

  /// Splits [message] into a list of [LogCommandParser]'s own command
  /// strings — each safe to feed straight into `LogCommandParser.parse`.
  /// Never empty in practice: the prompt asks for a single `"gibberish"`
  /// line rather than an empty array when nothing actionable was found,
  /// so that line can run through the exact same unrecognized-command
  /// path as any other line instead of the caller needing a special
  /// case for "nothing came back." Throws [GroqException] — never a
  /// partial/best-effort result — for a network failure, a non-200
  /// response, or a reply that isn't the JSON array of strings the
  /// prompt asked for.
  Future<List<String>> extractCommands(String message) async {
    try {
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer ${Env.groqApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'temperature': 0,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': message},
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw GroqException(
          "Couldn't reach the AI right now — try again in a moment.",
          cause: 'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      return _parseCommands(response.body);
    } on GroqException {
      rethrow;
    } on Object catch (error) {
      throw GroqException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    }
  }

  /// Digs the model's reply out of the chat-completions envelope, then
  /// decodes the JSON array it was asked for — tolerant of a stray
  /// code fence around it, since models add those despite being told
  /// not to. Throws [GroqException] (rather than degrading to an empty
  /// list) for anything that isn't that shape, so a malformed reply
  /// surfaces as a real error instead of silently doing nothing.
  List<String> _parseCommands(String responseBody) {
    final Object? content;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      final first = choices?.isNotEmpty == true
          ? choices!.first as Map<String, dynamic>
          : null;
      content = (first?['message'] as Map<String, dynamic>?)?['content'];
    } on FormatException catch (error) {
      throw GroqException("The AI's reply couldn't be read.", cause: error);
    }

    if (content is! String) {
      throw const GroqException("The AI didn't return anything usable.");
    }

    final cleaned = content
        .trim()
        .replaceAll(RegExp(r'^```(?:json)?|```$', multiLine: true), '')
        .trim();

    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (error) {
      throw GroqException("The AI's reply couldn't be read.", cause: error);
    }

    if (decoded is! List) {
      throw const GroqException("The AI's reply couldn't be read.");
    }

    return decoded
        .whereType<String>()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
