import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learn_quran/core/models/model_catalog.dart';
import 'package:learn_quran/core/services/model_download_service.dart';

const _testModel = ModelInfo(
  id: 'test',
  displayName: 'Test Model',
  description: 'A tiny fixture, not a real model',
  huggingFaceRepo: 'test/repo',
  filename: 'test-model.gguf',
  sizeBytes: 20,
);

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
      final client = MockClient((request) async {
        expect(request.url.toString(), _testModel.downloadUrl);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response.bytes(expectedBytes, 200);
      });
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      final progressUpdates = <DownloadProgress>[];
      await service.downloadModel(_testModel, onProgress: progressUpdates.add);

      final path = await service.localPathFor(_testModel);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(_testModel), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
      expect(progressUpdates.last.totalBytes, 20);
    });

    test('downloadModel resumes a partial file via a Range request', () async {
      final path = '${tempDir.path}/${_testModel.filename}';
      final firstHalf = List<int>.generate(10, (i) => 65 + i); // 'A'..'J'
      final secondHalf = List<int>.generate(10, (i) => 75 + i); // 'K'..'T'
      await File(path).writeAsBytes(firstHalf);

      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=10-');
        return http.Response.bytes(secondHalf, 206);
      });
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      await service.downloadModel(_testModel);

      expect(await File(path).readAsBytes(), [...firstHalf, ...secondHalf]);
      expect(await service.isDownloaded(_testModel), isTrue);
    });

    test('downloadModel restarts instead of appending when the server ignores Range', () async {
      final path = '${tempDir.path}/${_testModel.filename}';
      await File(path).writeAsBytes(List.filled(10, 65));
      final fullBody = List<int>.generate(20, (i) => 65 + i);

      // Server responds 200 (whole file) even though we sent a Range header —
      // must not append fullBody onto the stale partial bytes.
      final client = MockClient((request) async => http.Response.bytes(fullBody, 200));
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      await service.downloadModel(_testModel);

      expect(await File(path).readAsBytes(), fullBody);
    });

    test('downloadModel throws on a non-2xx response', () async {
      final client = MockClient((request) async => http.Response('not found', 404));
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);

      expect(() => service.downloadModel(_testModel), throwsException);
    });

    test('deleteModel removes the downloaded file', () async {
      final client = MockClient(
        (request) async => http.Response.bytes(List.filled(20, 65), 200),
      );
      final service = ModelDownloadService.forTesting(modelsDir: tempDir, client: client);
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
