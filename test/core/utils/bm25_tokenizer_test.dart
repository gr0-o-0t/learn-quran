import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/bm25_tokenizer.dart';

void main() {
  group('tokenizeForBm25', () {
    test('lowercases and splits on non-word characters', () {
      expect(tokenizeForBm25('Patience, Sabr! And Prayer.'), ['patience', 'sabr', 'prayer']);
    });

    test('drops common stopwords', () {
      expect(tokenizeForBm25('the patience of the prophet'), ['patience', 'prophet']);
    });

    test('drops single-character tokens', () {
      expect(tokenizeForBm25('a b patience c'), ['patience']);
    });

    test('returns an empty list for text with no indexable terms', () {
      expect(tokenizeForBm25('the a an'), isEmpty);
    });
  });
}
