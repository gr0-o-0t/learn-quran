/// A downloadable GGUF model tier.
class ModelInfo {
  final String id;
  final String displayName;
  final String description;
  final String huggingFaceRepo;
  final String filename;
  final int sizeBytes;

  /// The exact commit this model's URL is pinned to, so the file's size
  /// and content can never silently change out from under an already-
  /// downloaded exact-size match — unlike resolving against a mutable
  /// branch like `main`, where an upstream re-upload would permanently
  /// break isDownloaded's exact-size check with no visible error.
  final String revision;

  /// If non-null, this model becomes the recommendation once the device's
  /// detected RAM meets or exceeds this many GB. The catalog entry with a
  /// null threshold is the default/fallback recommendation.
  final double? recommendedAboveRamGb;

  const ModelInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.huggingFaceRepo,
    required this.filename,
    required this.sizeBytes,
    required this.revision,
    this.recommendedAboveRamGb,
  });

  String get downloadUrl =>
      'https://huggingface.co/$huggingFaceRepo/resolve/$revision/$filename';
}

/// The fixed, curated set of models users can download. Sizes verified
/// against the real Hugging Face files as of 2026-07-05 (Q4_K_M
/// quantizations from unsloth's Gemma 4 GGUF mirrors — Google's own
/// official repos are gated behind Hugging Face auth + license
/// acceptance, which isn't feasible for an anonymous in-app download).
const List<ModelInfo> kModelCatalog = [
  ModelInfo(
    id: 'e2b',
    displayName: 'Gemma 4 E2B (Lighter)',
    description: 'Recommended for devices with <6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E2B-it-GGUF',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    revision: 'ecc8b33b2c50598815e4b0f7cea6088e3ae7adb8',
    sizeBytes: 3106736256,
  ),
  ModelInfo(
    id: 'e4b',
    displayName: 'Gemma 4 E4B (Standard)',
    description: 'Recommended for devices with ≥6GB RAM',
    huggingFaceRepo: 'unsloth/gemma-4-E4B-it-GGUF',
    filename: 'gemma-4-E4B-it-Q4_K_M.gguf',
    revision: 'e1d90e5fb9f61d8dc71ef016580784a054e5c787',
    sizeBytes: 4977169568,
    recommendedAboveRamGb: 6.0,
  ),
];

/// Picks the highest-tier catalog entry whose [ModelInfo.recommendedAboveRamGb]
/// the device's RAM meets, falling back to the first (lowest-tier) entry.
ModelInfo recommendedModelFor(double ramGb) {
  var best = kModelCatalog.first;
  for (final model in kModelCatalog) {
    final threshold = model.recommendedAboveRamGb;
    if (threshold != null && ramGb >= threshold) {
      best = model;
    }
  }
  return best;
}

/// Looks up a catalog entry by id, falling back to the first entry if [id]
/// doesn't match anything (e.g. a stale/corrupted persisted setting).
ModelInfo modelById(String id) => kModelCatalog.firstWhere(
      (m) => m.id == id,
      orElse: () => kModelCatalog.first,
    );
