import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/services/import_job.dart';
import 'package:recipe_vault/services/recipe_ai_parser.dart';
import 'package:recipe_vault/services/video_recipe_parser.dart';
import 'package:recipe_vault/services/windows_recipe_ai.dart';
import 'fixtures/video_recipe_sample.dart';

class TrackingClient extends MockClient {
  bool closed = false;
  TrackingClient(super.handler);
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late Map<String, dynamic> start;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, dynamic> request({List<String>? schemas}) => {
    'id': 41,
    'modelPath': r'C:\Пользователи\Имя\ИИ\рецепт.gguf',
    'instruction': recipeAiInstruction,
    'schema': jsonEncode(recipeAiSchema),
    'fragments': ['[1] Берём 200 г муки.', '[1] Добавляем молоко.'],
    'fragmentSchemas': ?schemas,
  };
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(WindowsRecipeAi.channel, (call) async {
      calls.add(call);
      if (call.method == 'start') {
        start = Map<String, dynamic>.from(call.arguments as Map);
      }
      return call.method == 'running' ? true : null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(WindowsRecipeAi.channel, null),
  );

  test(
    'each fragment uses constrained JSON, no thinking, fresh context and private authorization',
    () async {
      var completions = 0;
      final client = TrackingClient((req) async {
        expect(req.url.host, '127.0.0.1');
        expect(req.url.port, 54321);
        expect(req.headers['Authorization'], 'Bearer ${start['key']}');
        expect((start['key'] as String).length, 64);
        if (req.url.path == '/health') return http.Response('{}', 200);
        final body = jsonDecode(req.body) as Map;
        expect(body['temperature'], 0);
        expect(body['seed'], 42);
        expect(body['stream'], false);
        expect(body['cache_prompt'], false);
        expect(body['prompt'], endsWith('<think>\n\n</think>\n\n'));
        expect(
          body['prompt'],
          contains(completions == 0 ? '200 г муки' : 'молоко'),
        );
        expect(body['json_schema'], recipeAiSchema);
        completions++;
        return http.Response(
          jsonEncode({'content': '{"fragment":$completions}'}),
          200,
        );
      });
      final result = await WindowsRecipeAi(
        createClient: () => client,
        reservePort: () async => 54321,
      ).extract(request(), job: ImportJob());
      expect(result['outputs'], ['{"fragment":1}', '{"fragment":2}']);
      expect(calls.map((c) => c.method), ['start', 'stop']);
      expect(client.closed, true);
    },
  );

  test('multi-recipe fragments carry separate allowed-index schemas', () async {
    final schemas = [
      for (final i in [1, 2]) videoStepsSchema(2, indexes: [i]),
    ];
    var index = 0;
    final client = TrackingClient((req) async {
      if (req.url.path == '/health') return http.Response('{}', 200);
      expect((jsonDecode(req.body) as Map)['json_schema'], schemas[index++]);
      return http.Response('{"content":"{}"}', 200);
    });
    await WindowsRecipeAi(
      createClient: () => client,
      reservePort: () async => 54321,
    ).extract(
      request(schemas: schemas.map(jsonEncode).toList()),
      job: ImportJob(),
    );
    expect(index, 2);
    expect(outlines.length, 2);
  });

  test(
    'cancelling during generation stops the worker and closes networking',
    () async {
      final job = ImportJob();
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final client = TrackingClient((req) async {
        if (req.url.path == '/health') return http.Response('{}', 200);
        started.complete();
        return pending.future;
      });
      final result = WindowsRecipeAi(
        createClient: () => client,
        reservePort: () async => 54321,
      ).extract(request(), job: job);
      final expectation = expectLater(result, throwsA(isA<ImportCancelled>()));
      await started.future;
      job.cancel();
      pending.completeError(const FormatException('closed transport'));
      await expectation;
      expect(client.closed, true);
      expect(calls.last.method, 'stop');
      expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    },
  );

  test(
    'timeouts, runtime crashes and invalid responses release the worker',
    () async {
      for (final failure in ['timeout', 'crash', 'invalid', 'oversize']) {
        messenger.setMockMethodCallHandler(WindowsRecipeAi.channel, (
          call,
        ) async {
          calls.add(call);
          return call.method == 'running' ? false : null;
        });
        final client = TrackingClient((req) async {
          if (req.url.path == '/health') {
            return http.Response('{}', failure == 'crash' ? 503 : 200);
          }
          if (failure == 'timeout') throw TimeoutException('inference timeout');
          return http.Response(
            failure == 'oversize' ? 'x' * 256001 : 'invalid json',
            200,
          );
        });
        await expectLater(
          WindowsRecipeAi(
            createClient: () => client,
            reservePort: () async => 54321,
          ).extract(request(), job: ImportJob()),
          throwsA(anything),
        );
        expect(client.closed, true, reason: failure);
        expect(calls.last.method, 'stop', reason: failure);
      }
    },
  );

  test(
    'a truncated response cannot masquerade as a complete fragment',
    () async {
      final client = TrackingClient(
        (req) async => req.url.path == '/health'
            ? http.Response('{}', 200)
            : http.Response('{"content":"{}","stop_type":"limit"}', 200),
      );
      final result = await WindowsRecipeAi(
        createClient: () => client,
        reservePort: () async => 54321,
      ).extract(request(), job: ImportJob());
      expect(result['outputs'], ['', '']);
    },
  );
}
