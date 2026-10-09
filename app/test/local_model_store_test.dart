import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/services/import_job.dart';
import 'package:recipe_vault/services/local_model_store.dart';

void main() {
  late Directory directory;
  late LocalModelStore store;
  final bytes = utf8.encode('verified model fixture');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('recipe-model-test');
    store = LocalModelStore(
      directory,
      url: Uri.parse('https://models.example.com/model'),
      expectedSize: bytes.length,
      expectedChecksum: sha256.convert(bytes).toString(),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('only a fully downloaded and verified model becomes ready', () async {
    await store.download(
      job: ImportJob(),
      onProgress: (_, _) {},
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    expect(await store.ready, true);
    expect(await store.file.readAsBytes(), bytes);
    expect(await store.partial.exists(), false);
  });
  test('ready model is not duplicated by another download', () async {
    await store.file.writeAsBytes(bytes);
    await store.partial.writeAsBytes(bytes.take(8).toList());
    await store.download(
      job: ImportJob(),
      onProgress: (_, _) {},
      client: MockClient((_) async => throw StateError('must not request')),
    );
    expect(await store.file.readAsBytes(), bytes);
    expect(await store.partial.exists(), false);
  });
  test('obsolete model is removed before replacement starts', () async {
    await store.file.writeAsBytes(List.filled(bytes.length + 10, 0));
    await store.download(
      job: ImportJob(),
      onProgress: (_, _) {},
      client: MockClient((_) async {
        expect(await store.file.exists(), false);
        return http.Response.bytes(bytes, 200);
      }),
    );
    expect(await store.file.readAsBytes(), bytes);
  });
  test('corrupt same-size file never becomes ready', () async {
    await expectLater(
      store.download(
        job: ImportJob(),
        onProgress: (_, _) {},
        client: MockClient(
          (_) async => http.Response.bytes(List.filled(bytes.length, 0), 200),
        ),
      ),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(await store.ready, false);
    expect(await store.partial.exists(), false);
  });
  test('interrupted download resumes with a validated byte range', () async {
    await store.partial.writeAsBytes(bytes.take(8).toList());
    await store.download(
      job: ImportJob(),
      onProgress: (_, _) {},
      client: MockClient((request) async {
        expect(request.headers['Range'], 'bytes=8-');
        return http.Response.bytes(
          bytes.skip(8).toList(),
          206,
          headers: {
            'content-range': 'bytes 8-${bytes.length - 1}/${bytes.length}',
          },
        );
      }),
    );
    expect(await store.ready, true);
    expect(await store.file.readAsBytes(), bytes);
  });
  test(
    'server ignoring range restarts file instead of appending duplicate data',
    () async {
      await store.partial.writeAsBytes(bytes.take(8).toList());
      await store.download(
        job: ImportJob(),
        onProgress: (_, _) {},
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      expect(await store.file.readAsBytes(), bytes);
    },
  );
  test(
    'wrong range is rejected and preserved partial remains resumable',
    () async {
      await store.partial.writeAsBytes(bytes.take(8).toList());
      await expectLater(
        store.download(
          job: ImportJob(),
          onProgress: (_, _) {},
          client: MockClient(
            (_) async => http.Response.bytes(
              bytes.skip(8).toList(),
              206,
              headers: {'content-range': 'bytes 0-13/22'},
            ),
          ),
        ),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(await store.ready, false);
      expect(await store.partial.length(), 8);
    },
  );
  test(
    'cancellation never promotes a partial file or starts a request',
    () async {
      final job = ImportJob()..cancel();
      await expectLater(
        store.download(
          job: job,
          onProgress: (_, _) {},
          client: MockClient((_) async => throw StateError('must not request')),
        ),
        throwsA(isA<ImportCancelled>()),
      );
      expect(await store.ready, false);
    },
  );
}
