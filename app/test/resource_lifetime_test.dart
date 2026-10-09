import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/app_controller.dart';
import 'package:recipe_vault/services/import_job.dart';
import 'package:recipe_vault/services/import_service.dart';
import 'package:recipe_vault/services/local_model_store.dart';
import 'package:recipe_vault/services/storage.dart';
import 'webdav_controller_test.dart' show MemoryCloudStorage;

class TrackedClient extends http.BaseClient {
  int closes = 0, requests = 0;
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  TrackedClient(this.respond);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return respond(request);
  }

  @override
  void close() => closes++;
}

void main() {
  test(
    'cancellation detaches completed stages and continues after cleanup errors',
    () {
      final job = ImportJob();
      var completed = 0, active = 0;
      final unregister = job.onCancel(() => completed++);
      unregister();
      job.onCancel(() => throw StateError('cleanup failed'));
      job.onCancel(() => active++);
      job.cancel();
      job.cancel();
      expect(completed, 0);
      expect(active, 1);
      expect(job.check, throwsA(isA<ImportCancelled>()));
    },
  );

  test(
    'cancelling a pending import aborts its request and allows a retry',
    () async {
      final started = Completer<void>();
      var first = true;
      final client = TrackedClient((request) async {
        if (first) {
          first = false;
          started.complete();
          await (request as http.Abortable).abortTrigger;
          throw http.RequestAbortedException(request.url);
        }
        return http.StreamedResponse(
          Stream.value(utf8.encode('<title>Суп</title>')),
          200,
        );
      });
      final service = ImportService(client: client), job = ImportJob();
      final pending = service.parse(
        'https://example.com/recipe',
        server: '',
        job: job,
      );
      final failure = expectLater(pending, throwsA(isA<ImportCancelled>()));
      await started.future;
      job.cancel();
      await failure;
      final result = await service.parse(
        'https://example.com/recipe',
        server: '',
      );
      expect(result.recipes.single.sourceUrl, 'https://example.com/recipe');
      expect(client.closes, 0);
      client.close();
    },
  );

  test(
    'an oversized server response is stopped before decoding JSON',
    () async {
      final client = TrackedClient(
        (_) async => http.StreamedResponse(
          Stream.fromIterable([
            List.filled(1500001, 65),
            List.filled(1500001, 65),
          ]),
          200,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        ImportService(
          client: client,
        ).parse('Суп', server: 'https://example.com'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'completed model downloads release their cancellation registrations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recipe-lifetime-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bytes = utf8.encode('verified fixture');
      final client = TrackedClient(
        (_) async => http.StreamedResponse(Stream.value(bytes), 200),
      );
      final job = ImportJob();
      await LocalModelStore(
        directory,
        expectedSize: bytes.length,
        expectedChecksum: sha256.convert(bytes).toString(),
      ).download(job: job, client: client, onProgress: (_, _) {});
      expect(client.closes, 1);
      job.cancel();
      expect(
        client.closes,
        1,
        reason: 'a completed stage must not be retained and closed again',
      );
    },
  );

  test(
    'disposing the controller closes in-flight sync and prevents later requests',
    () async {
      final started = Completer<void>(),
          finish = Completer<http.StreamedResponse>();
      final client = TrackedClient((_) {
        started.complete();
        return finish.future;
      });
      final storage = MemoryCloudStorage();
      final controller = AppController(
        storage: storage,
        database: RecipeDatabase(),
        settings: AppSettings(
          deviceId: 'test',
          autoSync: false,
          yandexLogin: 'fixture',
        ),
        syncClientFactory: () => client,
      );
      await controller.updateSettings(
        controller.settings,
        '',
        '',
        webDavSecret: 'synthetic-password',
      );
      final pending = controller.sync();
      await started.future;
      controller.dispose();
      expect(client.closes, 1);
      finish.completeError(http.ClientException('closed'));
      await pending;
      await controller.sync();
      await controller.checkWebDavConnection();
      expect(client.requests, 1);
      expect(storage.saved, isNull);
    },
  );

  testWidgets(
    'controller disposal during initialization cannot leave a periodic timer',
    (tester) async {
      final controller = AppController(
        storage: MemoryCloudStorage(),
        database: RecipeDatabase(),
        settings: AppSettings(deviceId: 'fixture'),
      );
      final initialization = controller.initialize();
      controller.dispose();
      await initialization;
      controller.autoSync();
      // flutter_test also fails this test if a periodic timer remains alive.
    },
  );
}
