import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/model_catalog.dart';
import 'package:learn_quran/core/services/model_download_service.dart';

const _testModel = ModelInfo(
  id: 'test',
  displayName: 'Test Model',
  description: 'A tiny fixture, not a real model',
  huggingFaceRepo: 'test/repo',
  filename: 'test-model.gguf',
  revision: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
  sizeBytes: 20,
);

/// Fakes [FileDownloader.download]: writes [bytes] to the task's own file
/// path (exactly like the real plugin would, once a transfer completes) and
/// reports one progress update, without ever touching the network or the
/// platform channel background_downloader normally uses.
DownloadFn _fakeDownloadWriting(List<int> bytes, {TaskStatus status = TaskStatus.complete}) {
  return (task, {onProgress}) async {
    if (status == TaskStatus.complete) {
      await File(await task.filePath()).writeAsBytes(bytes);
      onProgress?.call(1.0);
    }
    return TaskStatusUpdate(task, status);
  };
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelDownloadService', () {
    test('isDownloaded is false when no file exists', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      expect(await service.isDownloaded(_testModel), isFalse);
    });

    test('isDownloaded is false for a partial-size file, true once complete', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      final path = await service.localPathFor(_testModel);
      await File(path).writeAsBytes(List.filled(10, 65)); // 10 of 20 bytes
      expect(await service.isDownloaded(_testModel), isFalse);

      await File(path).writeAsBytes(List.filled(20, 65)); // now 20 of 20
      expect(await service.isDownloaded(_testModel), isTrue);
    });

    test('downloadModel writes the full response body to the expected path', () async {
      final expectedBytes = List<int>.generate(20, (i) => 65 + i); // 'A'..'T'
      final service = ModelDownloadService.forTesting(
        modelsDir: tempDir,
        download: _fakeDownloadWriting(expectedBytes),
      );

      final progressUpdates = <DownloadProgress>[];
      await service.downloadModel(_testModel, onProgress: progressUpdates.add);

      final path = await service.localPathFor(_testModel);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(_testModel), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
      expect(progressUpdates.last.totalBytes, 20);
    });

    test('downloadModel is a no-op if the file is already fully downloaded', () async {
      final service = ModelDownloadService.forTesting(
        modelsDir: tempDir,
        download: (task, {onProgress}) => throw StateError('should not be called'),
      );
      final path = await service.localPathFor(_testModel);
      await File(path).writeAsBytes(List.filled(20, 65));

      final progressUpdates = <DownloadProgress>[];
      await service.downloadModel(_testModel, onProgress: progressUpdates.add);

      expect(progressUpdates.single.bytesReceived, 20);
    });

    test('downloadModel throws for a non-complete status', () async {
      final service = ModelDownloadService.forTesting(
        modelsDir: tempDir,
        download: _fakeDownloadWriting(const [], status: TaskStatus.notFound),
      );

      expect(() => service.downloadModel(_testModel), throwsException);
    });

    test('downloadModel throws ModelDownloadCancelledException when the task is canceled', () async {
      final service = ModelDownloadService.forTesting(
        modelsDir: tempDir,
        download: _fakeDownloadWriting(const [], status: TaskStatus.canceled),
      );

      await expectLater(
        () => service.downloadModel(_testModel),
        throwsA(isA<ModelDownloadCancelledException>()),
      );
    });

    test('deleteModel removes the downloaded file', () async {
      final service = ModelDownloadService.forTesting(
        modelsDir: tempDir,
        download: _fakeDownloadWriting(List.filled(20, 65)),
      );
      await service.downloadModel(_testModel);
      expect(await service.isDownloaded(_testModel), isTrue);

      await service.deleteModel(_testModel);

      expect(await service.isDownloaded(_testModel), isFalse);
    });

    test('deleteModel on a non-existent file does not throw', () async {
      final service = ModelDownloadService.forTesting(modelsDir: tempDir);
      await service.deleteModel(_testModel); // should complete without error
    });
  });
}
