final _sentenceBoundary = RegExp(r'(?<=[.!?])\s+');

/// Splits [text] into chunks of roughly [maxTokens] tokens (measured by
/// [countTokens]), grouping whole sentences greedily and never splitting
/// mid-sentence. A single sentence that alone exceeds [maxTokens] becomes
/// its own (over-budget) chunk rather than being cut apart.
///
/// Returns a single-element list containing all of [text] unchanged if it
/// already fits within [maxTokens] — the common case for short entries.
/// Returns an empty list for empty/blank input.
List<String> chunkText(
  String text, {
  required int maxTokens,
  required int Function(String) countTokens,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (countTokens(trimmed) <= maxTokens) return [trimmed];

  final sentences = trimmed.split(_sentenceBoundary).where((s) => s.trim().isNotEmpty).toList();
  final chunks = <String>[];
  final currentSentences = <String>[];
  var currentTokens = 0;

  for (final sentence in sentences) {
    final sentenceTokens = countTokens(sentence);
    if (currentSentences.isNotEmpty && currentTokens + sentenceTokens > maxTokens) {
      chunks.add(currentSentences.join(' '));
      currentSentences.clear();
      currentTokens = 0;
    }
    currentSentences.add(sentence);
    currentTokens += sentenceTokens;
  }
  if (currentSentences.isNotEmpty) {
    chunks.add(currentSentences.join(' '));
  }
  return chunks;
}
