import 'dart:async';
import 'dart:io';
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
    final path = await localPathFor(kb);
    final file = File(path);
    final existingLength = await file.exists() ? await file.length() : 0;

    if (existingLength == kb.sizeBytes) {
      onProgress?.call(KbDownloadProgress(existingLength, kb.sizeBytes));
      return;
    }

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
    final sink = file.openWrite(mode: resuming ? FileMode.append : FileMode.write);
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
  }

  void cancelDownload() {
    _cancelRequested = true;
  }

  Future<void> deleteKb(KbInfo kb) async {
    final file = File(await localPathFor(kb));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
