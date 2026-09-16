import 'dart:convert';

import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final ok = jsonEncode({
    'items': [
      {
        'id': 'gb-dune',
        'volumeInfo': {
          'title': 'Dune',
          'authors': ['Frank Herbert'],
        },
      },
    ],
  });

  GoogleBooksApiClient clientAnswering(List<int> statuses, List<int> calls) =>
      GoogleBooksApiClient(
        client: MockClient((_) async {
          final status = statuses[calls.length.clamp(0, statuses.length - 1)];
          calls.add(status);
          return http.Response(status == 200 ? ok : 'busy', status);
        }),
        authHeaders: () async => const {},
        retryDelays: const [Duration.zero, Duration.zero],
      );

  test('a 503 from Google is retried, and a later answer wins', () async {
    final calls = <int>[];
    final results = await clientAnswering([
      503,
      503,
      200,
    ], calls).search('dune');

    expect(results.single.title, 'Dune');
    expect(calls, [503, 503, 200]);
  });

  test(
    'a 429 is not retried — a spent quota will not clear in seconds',
    () async {
      final calls = <int>[];
      await expectLater(
        clientAnswering([429, 200], calls).search('dune'),
        throwsA(isA<NetworkException>()),
      );
      expect(calls, [429]);
    },
  );

  test('gives up after the retries, as a retryable network error', () async {
    final calls = <int>[];
    await expectLater(
      clientAnswering([503], calls).search('dune'),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, hasLength(3));
  });

  test('a 400 is not retried', () async {
    final calls = <int>[];
    await expectLater(
      clientAnswering([400], calls).search('dune'),
      throwsA(isA<RemoteDataException>()),
    );
    expect(calls, hasLength(1));
  });
}
