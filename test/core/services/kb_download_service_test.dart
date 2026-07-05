import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:learn_quran/core/models/kb_catalog.dart';
import 'package:learn_quran/core/services/kb_download_service.dart';

const _testKb = KbInfo(version: 'test', filename: 'kb-test.db', sizeBytes: 20);

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
      final client = MockClient((request) async {
        expect(request.url.toString(), _testKb.downloadUrl);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response.bytes(expectedBytes, 200);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      final progressUpdates = <KbDownloadProgress>[];
      await service.downloadKb(_testKb, onProgress: progressUpdates.add);

      final path = await service.localPathFor(_testKb);
      expect(await File(path).readAsBytes(), expectedBytes);
      expect(await service.isDownloaded(_testKb), isTrue);
      expect(progressUpdates.last.bytesReceived, 20);
    });

    test('downloadKb resumes a partial file via a Range request', () async {
      final path = '${tempDir.path}/${_testKb.filename}';
      final firstHalf = List<int>.generate(10, (i) => 65 + i);
      final secondHalf = List<int>.generate(10, (i) => 75 + i);
      await File(path).writeAsBytes(firstHalf);

      final client = MockClient((request) async {
        expect(request.headers['Range'], 'bytes=10-');
        return http.Response.bytes(secondHalf, 206);
      });
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);

      await service.downloadKb(_testKb);

      expect(await File(path).readAsBytes(), [...firstHalf, ...secondHalf]);
    });

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

    test('deleteKb removes the downloaded file', () async {
      final client = MockClient((request) async => http.Response.bytes(List.filled(20, 65), 200));
      final service = KbDownloadService.forTesting(kbDir: tempDir, client: client);
      await service.downloadKb(_testKb);
      expect(await service.isDownloaded(_testKb), isTrue);

      await service.deleteKb(_testKb);

      expect(await service.isDownloaded(_testKb), isFalse);
    });
  });
}
