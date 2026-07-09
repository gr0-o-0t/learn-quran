import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/services/reranker_service.dart';

void main() {
  group('RerankerService', () {
    test('forceMock returns null (unavailable) without touching ONNX', () async {
      final service = RerankerService(forceMock: true);
      final score = await service.score('a query', 'a passage');
      expect(score, isNull);
    });

    test('scoreOverride bypasses the real model entirely, for both text and score', () async {
      final service = RerankerService(
        scoreOverride: (query, passage) async => passage.contains('relevant') ? 5.0 : -5.0,
      );
      expect(await service.score('q', 'this is relevant text'), 5.0);
      expect(await service.score('q', 'this is off-topic text'), -5.0);
    });

    test('scoreOverride receives the exact query and passage text passed in', () async {
      String? capturedQuery;
      String? capturedPassage;
      final service = RerankerService(
        scoreOverride: (query, passage) async {
          capturedQuery = query;
          capturedPassage = passage;
          return 0.0;
        },
      );
      await service.score('the query text', 'the passage text');
      expect(capturedQuery, 'the query text');
      expect(capturedPassage, 'the passage text');
    });
  });
}
