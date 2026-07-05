import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
/// lingers around to poison a future resume attempt.
class KbIntegrityException implements Exception {
  final String expected;
  final String actual;
  const KbIntegrityException({required this.expected, required this.actual});

  @override
  String toString() => 'KbIntegrityException: expected sha256 $expected but '
      'downloaded content hashed to $actual';
}

class KbDownloadService {
  static const _defaultIdleTimeout = Duration(seconds: 30);

  final http.Client _client;
  final Directory? _kbDirOverride;
  final Duration _idleTimeout;
  bool _cancelRequested = false;

  KbDownloadService({http.Client? client})
      : _client = client ?? http.Client(),
        _kbDirOverride = null,
        _idleTimeout = _defaultIdleTimeout;

  KbDownloadService.forTesting({
    required Directory kbDir,
    http.Client? client,
    Duration idleTimeout = _defaultIdleTimeout,
  })  : _client = client ?? http.Client(),
        _kbDirOverride = kbDir,
        _idleTimeout = idleTimeout;

  Future<Directory> _kbBaseDir() async {
    final override = _kbDirOverride;
    if (override != null) return override;
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/kb');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> localPathFor(KbInfo kb) async {
    final dir = await _kbBaseDir();
    return '${dir.path}/${kb.filename}';
  }

  /// Staging path a download is written/resumed against. Kept separate from
  /// [localPathFor] so a fresh, empty schema-only database file that Drift
  /// may have already created at the production path (see
  /// `openKnowledgeBaseDatabase`) can never be mistaken for a genuine
  /// partial download of this exact resource, and so the production path
  /// only ever holds a complete, hash-verified file.
  Future<String> _partPathFor(KbInfo kb) async => '${await localPathFor(kb)}.part';

  Future<bool> isDownloaded(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (!await file.exists()) return false;
    return await file.length() == kb.sizeBytes;
  }

  Future<void> downloadKb(
    KbInfo kb, {
    void Function(KbDownloadProgress)? onProgress,
  }) async {
    _cancelRequested = false;
    final finalPath = await localPathFor(kb);

    if (await isDownloaded(kb)) {
      onProgress?.call(KbDownloadProgress(kb.sizeBytes, kb.sizeBytes));
      return;
    }

    final partPath = await _partPathFor(kb);
    final partFile = File(partPath);
    final existingLength = await partFile.exists() ? await partFile.length() : 0;

    final validPartial = existingLength > 0 && existingLength < kb.sizeBytes;
    final request = http.Request('GET', Uri.parse(kb.downloadUrl));
    if (validPartial) {
      request.headers['Range'] = 'bytes=$existingLength-';
    }

    final response = await _client.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('Unexpected status ${response.statusCode} downloading knowledge base ${kb.version}');
    }

    final resuming = response.statusCode == 206 && validPartial;
    final sink = partFile.openWrite(mode: resuming ? FileMode.append : FileMode.write);
    var received = resuming ? existingLength : 0;

    try {
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        if (_cancelRequested) {
          throw KbDownloadCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(KbDownloadProgress(received, kb.sizeBytes));
      }
    } finally {
      await sink.close();
    }

    final actualHash = (await sha256.bind(partFile.openRead()).first).toString();
    if (actualHash != kb.sha256) {
      await partFile.delete();
      throw KbIntegrityException(expected: kb.sha256, actual: actualHash);
    }

    await partFile.rename(finalPath);
  }

  void cancelDownload() {
    _cancelRequested = true;
  }

  Future<void> deleteKb(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (await file.exists()) {
      await file.delete();
    }
    final partFile = File(await _partPathFor(kb));
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }
}
