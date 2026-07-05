import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Signature of [FileDownloader.download], narrowed to what this service
/// needs — lets tests substitute a fake that never touches the network or
/// the platform channel background_downloader normally uses.
typedef DownloadFn = Future<TaskStatusUpdate> Function(
  DownloadTask task, {
  void Function(double)? onProgress,
});

/// Downloads GGUF model files from Hugging Face to app-local storage via
/// [FileDownloader] (background_downloader), which uses native URLSessions
/// (iOS) / DownloadWorker (Android) so the transfer keeps running when the
/// screen locks or the app is backgrounded — unlike a hand-rolled `http`
/// stream, which is tied to this app's own isolate and stalls as soon as
/// the OS suspends it.
class ModelDownloadService {
  final DownloadFn _download;
  final Directory? _modelsDirOverride;
  String? _currentTaskId;

  ModelDownloadService({DownloadFn? download})
      : _download = download ?? _defaultDownload,
        _modelsDirOverride = null;

  /// For testing: [modelsDir] bypasses path_provider entirely (via
  /// `BaseDirectory.root`), and [download] can replace the real
  /// [FileDownloader] call with a fake that writes canned bytes directly.
  ModelDownloadService.forTesting({
    required Directory modelsDir,
    DownloadFn? download,
  })  : _modelsDirOverride = modelsDir,
        _download = download ?? _defaultDownload;

  static Future<TaskStatusUpdate> _defaultDownload(
    DownloadTask task, {
    void Function(double)? onProgress,
  }) =>
      FileDownloader().download(task, onProgress: onProgress);

  DownloadTask _taskFor(ModelInfo model) {
    final override = _modelsDirOverride;
    return DownloadTask(
      taskId: 'model-${model.id}',
      url: model.downloadUrl,
      filename: model.filename,
      baseDirectory: override != null ? BaseDirectory.root : BaseDirectory.applicationDocuments,
      directory: override != null ? override.path : 'models',
      updates: Updates.progress,
      allowPause: true,
      retries: 3,
    );
  }

  Future<String> localPathFor(ModelInfo model) => _taskFor(model).filePath();

  /// True only if the local file exists AND its size matches
  /// [ModelInfo.sizeBytes] exactly — a partial/interrupted download must
  /// never read as "downloaded".
  Future<bool> isDownloaded(ModelInfo model) async {
    final file = File(await localPathFor(model));
    if (!await file.exists()) return false;
    return await file.length() == model.sizeBytes;
  }

  /// Downloads (or resumes) [model], calling [onProgress] as bytes arrive.
  Future<void> downloadModel(
    ModelInfo model, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    if (await isDownloaded(model)) {
      onProgress?.call(DownloadProgress(model.sizeBytes, model.sizeBytes));
      return;
    }

    final task = _taskFor(model);
    _currentTaskId = task.taskId;
    final TaskStatusUpdate result;
    try {
      result = await _download(
        task,
        onProgress: (progress) {
          if (progress >= 0) {
            onProgress?.call(DownloadProgress((progress * model.sizeBytes).round(), model.sizeBytes));
          }
        },
      );
    } finally {
      _currentTaskId = null;
    }

    if (result.status == TaskStatus.canceled) {
      throw ModelDownloadCancelledException();
    }
    if (result.status != TaskStatus.complete) {
      throw HttpException(
        'Failed to download ${model.displayName}: ${result.status}'
        '${result.exception != null ? ' (${result.exception})' : ''}',
      );
    }
  }

  /// Signals the in-flight [downloadModel] call (if any) to stop. The
  /// partial file is left on disk so a later call can resume from it.
  void cancelDownload() {
    final taskId = _currentTaskId;
    if (taskId != null) {
      FileDownloader().cancelTaskWithId(taskId);
    }
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
