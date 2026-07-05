import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

class _StallingClient extends http.BaseClient {
  final List<int> initialBytes;
  _StallingClient(this.initialBytes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // ignore: close_sinks — deliberately never closed, to simulate a stall.
    final controller = StreamController<List<int>>();
    controller.add(initialBytes);
    return http.StreamedResponse(controller.stream, 200, contentLength: 20);
  }
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
      final client = MockClient((request) async {
        expect(request.url.toString(), testKb.downloadUrl);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response.bytes(expectedBytes, 200);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      final progressUpdates = <KbDownloadProgress>[];
      await service.downloadKb(testKb, onProgress: progressUpdates.add);

      final path = await service.localPathFor(testKb);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(testKb), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
      // The staging file must not be left behind after a successful download.
      expect(await File('$path.part').exists(), isFalse);
    });

    test('downloadKb resumes a partial file via a Range request', () async {
      final firstHalf = List<int>.generate(10, (i) => 65 + i);
      final secondHalf = List<int>.generate(10, (i) => 75 + i);
      final fullBytes = [...firstHalf, ...secondHalf];
      final testKb = KbInfo(
        version: 'test',
        filename: 'kb-test.db',
        sizeBytes: 20,
        sha256: sha256.convert(fullBytes).toString(),
      );
      // A genuine partial download resumes from the staging `.part` file,
      // never from the final path.
      final partPath = '${tempDir.path}/${testKb.filename}.part';
      await File(partPath).writeAsBytes(firstHalf);

      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=10-');
        return http.Response.bytes(secondHalf, 206);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      await service.downloadKb(testKb);

      final finalPath = await service.localPathFor(testKb);
      expect(await File(finalPath).readAsBytes(), fullBytes);
      expect(await File(partPath).exists(), isFalse);
    });

    test(
      'downloadKb ignores an unrelated file already sitting at the final path '
      '(e.g. a Drift-created empty schema database) instead of treating it as '
      'a resumable partial download',
      () async {
        final serverBytes = List<int>.generate(20, (i) => 200 + i);
        final testKb = KbInfo(
          version: 'test',
          filename: 'kb-test.db',
          sizeBytes: 20,
          sha256: sha256.convert(serverBytes).toString(),
        );
        final finalPath = '${tempDir.path}/${testKb.filename}';
        // Simulates the schema-only sqlite file Drift auto-creates at the
        // production path before anything has ever been downloaded: some
        // unrelated bytes, strictly between 0 and sizeBytes in length.
        await File(finalPath).writeAsBytes(List.filled(5, 99));

        final client = MockClient((request) async {
          // Must NOT be treated as a partial download of the unrelated file.
          expect(request.headers.containsKey('Range'), isFalse);
          return http.Response.bytes(serverBytes, 200);
        });
        final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

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
        final client = MockClient((request) async => http.Response.bytes(serverBytes, 200));
        final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

        await expectLater(
          () => service.downloadKb(testKb),
          throwsA(isA<KbIntegrityException>()),
        );

        final finalPath = await service.localPathFor(testKb);
        expect(await File(finalPath).exists(), isFalse);
        expect(await File('$finalPath.part').exists(), isFalse);
      },
    );

    test('downloadKb throws instead of hanging forever when the stream stalls', () async {
      final client = _StallingClient(List.filled(10, 65));
      final service = KbDownloadService.forTesting(
        kbDir: tempDir,
        client: client,
        idleTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        () => service.downloadKb(_testKb),
        throwsA(isA<TimeoutException>()),
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
      final client = MockClient((request) async => http.Response.bytes(bytes, 200));
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);
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
