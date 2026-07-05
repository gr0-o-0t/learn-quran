import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/model_catalog.dart';

/// Reports download progress. [fraction] is 0.0-1.0, or 0 if [totalBytes]
/// is unknown/zero.
class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const DownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

/// Thrown from [ModelDownloadService.downloadModel] when
/// [ModelDownloadService.cancelDownload] was called mid-download.
class ModelDownloadCancelledException implements Exception {
  @override
  String toString() => 'ModelDownloadCancelledException';
}

/// Downloads GGUF model files from Hugging Face to app-local storage,
/// resuming partial downloads via HTTP Range requests.
class ModelDownloadService {
  static const _defaultIdleTimeout = Duration(seconds: 30);

  final http.Client _client;
  final Directory? _modelsDirOverride;
  final Duration _idleTimeout;
  bool _cancelRequested = false;

  ModelDownloadService({http.Client? client})
      : _client = client ?? http.Client(),
        _modelsDirOverride = null,
        _idleTimeout = _defaultIdleTimeout;

  /// For testing: bypasses path_provider and stores/reads files directly
  /// under [modelsDir] instead of `<ApplicationDocumentsDirectory>/models`,
  /// and allows shrinking the stall-detection [idleTimeout] so tests don't
  /// have to wait out the real 30s production value.
  ModelDownloadService.forTesting({
    required Directory modelsDir,
    http.Client? client,
    Duration idleTimeout = _defaultIdleTimeout,
  })  : _client = client ?? http.Client(),
        _modelsDirOverride = modelsDir,
        _idleTimeout = idleTimeout;

  Future<Directory> _modelsDir() async {
    final override = _modelsDirOverride;
    if (override != null) return override;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> localPathFor(ModelInfo model) async {
    final dir = await _modelsDir();
    return '${dir.path}/${model.filename}';
  }

  /// True only if the local file exists AND its size matches
  /// [ModelInfo.sizeBytes] exactly — a partial/interrupted download must
  /// never read as "downloaded".
  Future<bool> isDownloaded(ModelInfo model) async {
    final file = File(await localPathFor(model));
    if (!await file.exists()) return false;
    return await file.length() == model.sizeBytes;
  }

  /// Downloads (or resumes) [model], calling [onProgress] as bytes arrive.
  /// If a partial file already exists and is smaller than
  /// [ModelInfo.sizeBytes], sends `Range: bytes=<existing-length>-` and
  /// appends the response to the existing file. If the server responds
  /// 200 (ignoring the Range request) rather than 206, the download
  /// restarts from scratch instead of appending onto stale bytes.
  Future<void> downloadModel(
    ModelInfo model, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    _cancelRequested = false;
    final path = await localPathFor(model);
    final file = File(path);
    final existingLength = await file.exists() ? await file.length() : 0;

    // Exact match only — this must agree with isDownloaded's exact-size
    // check. An oversized/corrupt file (> sizeBytes) falls through and
    // restarts the download below rather than silently no-op'ing forever.
    if (existingLength == model.sizeBytes) {
      onProgress?.call(DownloadProgress(existingLength, model.sizeBytes));
      return;
    }

    final validPartial = existingLength > 0 && existingLength < model.sizeBytes;
    final request = http.Request('GET', Uri.parse(model.downloadUrl));
    if (validPartial) {
      request.headers['Range'] = 'bytes=$existingLength-';
    }

    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException(
        'Unexpected status ${response.statusCode} downloading ${model.displayName}',
      );
    }

    final resuming = response.statusCode == 206 && validPartial;
    final sink = file.openWrite(
      mode: resuming ? FileMode.append : FileMode.write,
    );
    var received = resuming ? existingLength : 0;

    try {
      // ponytail: CDN downloads can stall silently mid-transfer (e.g. an
      // edge-cache miss on a specific pinned revision) with no error and no
      // more bytes — without an idle timeout that hangs the UI forever.
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        if (_cancelRequested) {
          throw ModelDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received, model.sizeBytes));
      }
    } finally {
      await sink.close();
    }
  }

  /// Signals the in-flight [downloadModel] call (if any) to stop after its
  /// next chunk. The partial file is left on disk so a later call can
  /// resume from it.
  void cancelDownload() {
    _cancelRequested = true;
  }

  Future<void> deleteModel(ModelInfo model) async {
    final file = File(await localPathFor(model));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService();
});
