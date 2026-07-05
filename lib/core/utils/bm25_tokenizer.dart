/// A tiny, deliberately simple tokenizer shared by tool/build_kb.dart (index
/// time) and Bm25Index (query time) — both MUST use the exact same rules,
/// or BM25 term lookups silently stop matching.
final _wordPattern = RegExp(r"[a-z0-9']+");

const _stopwords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'has',
  'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the', 'to', 'was',
  'were', 'will', 'with',
};

/// Lowercases [text], splits into word tokens, and drops single-character
/// tokens and common English stopwords.
List<String> tokenizeForBm25(String text) {
  return _wordPattern
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((word) => word.length > 1 && !_stopwords.contains(word))
      .toList();
}
