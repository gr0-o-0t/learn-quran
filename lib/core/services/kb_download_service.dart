import 'dart:async';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import '../models/kb_catalog.dart';

class KbDownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  const KbDownloadProgress(this.bytesReceived, this.totalBytes);
  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

class KbDownloadCancelledException implements Exception {
  @override
  String toString() => 'KbDownloadCancelledException';
}

/// Thrown when a fully-downloaded knowledge base file's sha256 doesn't match
/// [KbInfo.sha256]. The corrupt staging file is deleted before this is
/// thrown, so the bad content never lands at the production path and never
/// lingers around to poison a future download attempt.
class KbIntegrityException implements Exception {
  final String expected;
  final String actual;
  const KbIntegrityException({required this.expected, required this.actual});

  @override
  String toString() => 'KbIntegrityException: expected sha256 $expected but '
      'downloaded content hashed to $actual';
}

/// Signature of [FileDownloader.download], narrowed to what this service
/// needs — lets tests substitute a fake that never touches the network or
/// the platform channel background_downloader normally uses.
typedef DownloadFn = Future<TaskStatusUpdate> Function(
  DownloadTask task, {
  void Function(double)? onProgress,
});

/// Downloads the knowledge base via [FileDownloader] (background_downloader),
/// which uses native URLSessions (iOS) / DownloadWorker (Android) so the
/// transfer keeps running when the screen locks or the app is backgrounded —
/// unlike a hand-rolled `http` stream, which is tied to this app's own
/// isolate and stalls as soon as the OS suspends it.
///
/// Downloads are staged to `<kb.filename>.part` (never the path
/// `KnowledgeBaseDatabase`/Drift might have already created an empty
/// schema-only file at — see `database_provider.dart`) and only renamed to
/// the production path after its sha256 is verified, so a corrupt or
/// unrelated file can never be mistaken for a valid knowledge base.
class KbDownloadService {
  final DownloadFn _download;
  final Directory? _kbDirOverride;
  String? _currentTaskId;

  KbDownloadService({DownloadFn? download})
      : _download = download ?? _defaultDownload,
        _kbDirOverride = null;

  /// For testing: [kbDir] bypasses path_provider entirely (via
  /// `BaseDirectory.root`), and [download] can replace the real
  /// [FileDownloader] call with a fake that writes canned bytes directly.
  KbDownloadService.forTesting({
    required Directory kbDir,
    DownloadFn? download,
  })  : _kbDirOverride = kbDir,
        _download = download ?? _defaultDownload;

  static Future<TaskStatusUpdate> _defaultDownload(
    DownloadTask task, {
    void Function(double)? onProgress,
  }) =>
      FileDownloader().download(task, onProgress: onProgress);

  DownloadTask _partTaskFor(KbInfo kb) {
    final override = _kbDirOverride;
    return DownloadTask(
      taskId: 'kb-${kb.version}',
      url: kb.downloadUrl,
      filename: '${kb.filename}.part',
      baseDirectory: override != null ? BaseDirectory.root : BaseDirectory.applicationDocuments,
      directory: override != null ? override.path : 'kb',
      updates: Updates.progress,
      allowPause: true,
      retries: 3,
    );
  }

  Future<String> localPathFor(KbInfo kb) => _partTaskFor(kb).filePath(withFilename: kb.filename);

  Future<bool> isDownloaded(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (!await file.exists()) return false;
    return await file.length() == kb.sizeBytes;
  }

  Future<void> downloadKb(
    KbInfo kb, {
    void Function(KbDownloadProgress)? onProgress,
  }) async {
    final finalPath = await localPathFor(kb);
    if (await isDownloaded(kb)) {
      onProgress?.call(KbDownloadProgress(kb.sizeBytes, kb.sizeBytes));
      return;
    }

    final task = _partTaskFor(kb);
    _currentTaskId = task.taskId;
    final TaskStatusUpdate result;
    try {
      result = await _download(
        task,
        onProgress: (progress) {
          if (progress >= 0) {
            onProgress?.call(KbDownloadProgress((progress * kb.sizeBytes).round(), kb.sizeBytes));
          }
        },
      );
    } finally {
      _currentTaskId = null;
    }

    if (result.status == TaskStatus.canceled) {
      throw KbDownloadCancelledException();
    }
    if (result.status != TaskStatus.complete) {
      throw HttpException(
        'Failed to download knowledge base ${kb.version}: ${result.status}'
        '${result.exception != null ? ' (${result.exception})' : ''}',
      );
    }

    final partFile = File(await task.filePath());
    final actualHash = (await sha256.bind(partFile.openRead()).first).toString();
    if (actualHash != kb.sha256) {
      await partFile.delete();
      throw KbIntegrityException(expected: kb.sha256, actual: actualHash);
    }
    await partFile.rename(finalPath);
  }

  /// Signals the in-flight [downloadKb] call (if any) to stop. The staged
  /// `.part` file is left in place so a later call can resume from it.
  void cancelDownload() {
    final taskId = _currentTaskId;
    if (taskId != null) {
      FileDownloader().cancelTaskWithId(taskId);
    }
  }

  Future<void> deleteKb(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (await file.exists()) {
      await file.delete();
    }
    final partFile = File(await _partTaskFor(kb).filePath());
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }
}
