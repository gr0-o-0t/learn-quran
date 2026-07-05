import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';
import 'package:learn_quran/core/services/kb_download_service.dart';

/// Base fixture used by tests that don't care about the actual downloaded
/// content (its sha256 is never checked against real bytes in those cases).
final _testKb = KbInfo(
  version: 'test',
  filename: 'kb-test.db',
  sizeBytes: 20,
  sha256: sha256.convert(List.filled(20, 65)).toString(),
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
    tempDir = Directory.systemTemp.createTempSync('kb_download_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KbDownloadService', () {
    test('isDownloaded is false when no file exists', () async {
      final service = KbDownloadService.forTesting(kbDir: tempDir);
      expect(await service.isDownloaded(_testKb), isFalse);
    });

    test('downloadKb writes the full response body to the expected path', () async {
      final expectedBytes = List<int>.generate(20, (i) => 65 + i);
      final testKb = KbInfo(
        version: 'test',
        filename: 'kb-test.db',
        sizeBytes: 20,
        sha256: sha256.convert(expectedBytes).toString(),
      );
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        download: _fakeDownloadWriting(expectedBytes),
      );

      final progressUpdates = <KbDownloadProgress>[];
      await service.downloadKb(testKb, onProgress: progressUpdates.add);

      final path = await service.localPathFor(testKb);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(testKb), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
      // The staging file must not be left behind after a successful download.
      expect(await File('$path.part').exists(), isFalse);
    });

    test('downloadKb is a no-op if the file is already fully downloaded', () async {
      final bytes = List.filled(20, 65);
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        download: (task, {onProgress}) => throw StateError('should not be called'),
      );
      final path = await service.localPathFor(_testKb);
      await File(path).writeAsBytes(bytes);

      final progressUpdates = <KbDownloadProgress>[];
      await service.downloadKb(_testKb, onProgress: progressUpdates.add);

      expect(progressUpdates.single.bytesReceived, 20);
    });

    test(
      'downloadKb ends up with correct content even if an unrelated file '
      '(e.g. a Drift-created empty schema database) already sits at the '
      'final path — resume/staging decisions never look at that file',
      () async {
        final serverBytes = List<int>.generate(20, (i) => 200 + i);
        final testKb = KbInfo(
          version: 'test',
          filename: 'kb-test.db',
          sizeBytes: 20,
          sha256: sha256.convert(serverBytes).toString(),
        );
        final service = KbDownloadService.forTesting(
          kbDir: tempDir,
          download: _fakeDownloadWriting(serverBytes),
        );
        final finalPath = await service.localPathFor(testKb);
        // Simulates the schema-only sqlite file Drift auto-creates at the
        // production path before anything has ever been downloaded: some
        // unrelated bytes, strictly between 0 and sizeBytes in length.
        await File(finalPath).writeAsBytes(List.filled(5, 99));

        await service.downloadKb(testKb);

        expect(await File(finalPath).readAsBytes(), serverBytes);
        expect(await File('$finalPath.part').exists(), isFalse);
      },
    );

    test(
      'downloadKb throws KbIntegrityException and cleans up when the '
      'downloaded content does not match the expected sha256',
      () async {
        final serverBytes = List<int>.generate(20, (i) => 65 + i);
        final testKb = KbInfo(
          version: 'test',
          filename: 'kb-test.db',
          sizeBytes: 20,
          // Deliberately wrong — doesn't match serverBytes' real hash.
          sha256: sha256.convert(List.filled(20, 0)).toString(),
        );
        final service = KbDownloadService.forTesting(
          kbDir: tempDir,
          download: _fakeDownloadWriting(serverBytes),
        );

        await expectLater(
          () => service.downloadKb(testKb),
          throwsA(isA<KbIntegrityException>()),
        );

        final finalPath = await service.localPathFor(testKb);
        expect(await File(finalPath).exists(), isFalse);
        expect(await File('$finalPath.part').exists(), isFalse);
      },
    );

    test('downloadKb throws KbDownloadCancelledException when the task is canceled', () async {
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        download: _fakeDownloadWriting(const [], status: TaskStatus.canceled),
      );

      await expectLater(
        () => service.downloadKb(_testKb),
        throwsA(isA<KbDownloadCancelledException>()),
      );
    });

    test('downloadKb throws for any other non-complete status', () async {
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        download: _fakeDownloadWriting(const [], status: TaskStatus.failed),
      );

      await expectLater(
        () => service.downloadKb(_testKb),
        throwsA(isA<HttpException>()),
      );
    });

    test('deleteKb removes the downloaded file and any leftover staging file', () async {
      final bytes = List.filled(20, 65);
      final testKb = KbInfo(
        version: 'test',
        filename: 'kb-test.db',
        sizeBytes: 20,
        sha256: sha256.convert(bytes).toString(),
      );
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        download: _fakeDownloadWriting(bytes),
      );
      await service.downloadKb(testKb);
      expect(await service.isDownloaded(testKb), isTrue);

      // Simulate a leftover staging file from some earlier failed attempt.
      final finalPath = await service.localPathFor(testKb);
      await File('$finalPath.part').writeAsBytes([1, 2, 3]);

      await service.deleteKb(testKb);

      expect(await service.isDownloaded(testKb), isFalse);
      expect(await File('$finalPath.part').exists(), isFalse);
    });
  });
}
