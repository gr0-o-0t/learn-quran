import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/utils/text_chunking.dart';

int _wordCount(String s) => s.trim().split(RegExp(r'\s+')).length;

void main() {
  group('chunkText', () {
    test('returns the whole text as one chunk when it already fits', () {
      final result = chunkText('Short text here.', maxTokens: 10, countTokens: _wordCount);
      expect(result, ['Short text here.']);
    });

    test('returns an empty list for empty/blank input', () {
      expect(chunkText('', maxTokens: 10, countTokens: _wordCount), isEmpty);
      expect(chunkText('   ', maxTokens: 10, countTokens: _wordCount), isEmpty);
    });

    test('groups sentences into chunks without exceeding the token budget', () {
      // Each sentence is 3 words; a budget of 5 tokens fits at most one
      // sentence per chunk (adding a 2nd would be 6 tokens).
      const text = 'One two three. Four five six. Seven eight nine.';
      final result = chunkText(text, maxTokens: 5, countTokens: _wordCount);
      expect(result, [
        'One two three.',
        'Four five six.',
        'Seven eight nine.',
      ]);
    });

    test('groups multiple short sentences into one chunk when they fit together', () {
      const text = 'One two. Three four. Five six.';
      // Each sentence is 2 words; a budget of 4 tokens fits two sentences.
      final result = chunkText(text, maxTokens: 4, countTokens: _wordCount);
      expect(result, [
        'One two. Three four.',
        'Five six.',
      ]);
    });

    test('never splits mid-sentence, even if a single sentence exceeds the budget', () {
      const text = 'One two three four five. Six seven.';
      final result = chunkText(text, maxTokens: 3, countTokens: _wordCount);
      expect(result, [
        'One two three four five.', // over budget but kept whole
        'Six seven.',
      ]);
    });
  });
}
