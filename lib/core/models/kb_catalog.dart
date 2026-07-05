/// A downloadable, versioned knowledge base release.
class KbInfo {
  final String version;
  final String filename;
  final int sizeBytes;

  const KbInfo({
    required this.version,
    required this.filename,
    required this.sizeBytes,
  });

  String get downloadUrl =>
      'https://github.com/REPLACE_WITH_ORG/learn-quran/releases/download/kb-v$version/$filename';
}

/// The current knowledge base version the app knows how to fetch.
/// sizeBytes is filled in for real once kb-v1.0.0 is actually built and
/// published (see docs/superpowers/plans/2026-07-05-knowledge-base-v1.md,
/// Task 9's final step) — do not trust this value until that step is done.
const KbInfo kCurrentKb = KbInfo(
  version: '1.0.0',
  filename: 'kb.db',
  sizeBytes: 0, // TODO(Task 9, final step): replace with the real, verified byte count.
);
