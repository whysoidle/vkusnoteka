import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'import_job.dart';
import 'windows_ai_protocol.dart';

/// The bundled worker exists only while an import is running. Windows owns it
/// in a kill-on-close Job Object, including when the Flutter process crashes.
class WindowsRecipeAi {
  static const channel = MethodChannel('recipe_vault/local_ai');
  final http.Client Function() _createClient;
  final Future<int> Function() _reservePort;
  final Duration startupTimeout;
  final Duration requestTimeout;
  WindowsRecipeAi({
    http.Client Function()? createClient,
    Future<int> Function()? reservePort,
    this.startupTimeout = const Duration(minutes: 3),
    this.requestTimeout = const Duration(minutes: 10),
  }) : _createClient = createClient ?? _directClient,
       _reservePort = reservePort ?? _freePort;

  static http.Client _directClient() {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 2);
    return IOClient(client);
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<Map<String, dynamic>> extract(
    Map<String, dynamic> arguments, {
    required ImportJob job,
    void Function(String)? onProgress,
  }) async {
    job.check();
    final id = arguments['id'] as int;
    final port = await _reservePort();
    job.check();
    final random = Random.secure();
    final key = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final client = _createClient();
    final headers = {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    };
    Uri endpoint(String path) =>
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: path);
    Future<void> stop() async {
      await channel.invokeMethod<void>('stop', {'id': id});
    }

    final unregister = job.onCancel(() {
      client.close();
      unawaited(stop().catchError((Object _) {}));
    });
    try {
      job.check();
      await channel.invokeMethod<void>('start', {
        'id': id,
        'modelPath': arguments['modelPath'],
        'port': port,
        'key': key,
        'threads': Platform.numberOfProcessors.clamp(1, 8),
      });
      job.check();
      final deadline = DateTime.now().add(startupTimeout);
      while (true) {
        job.check();
        if (DateTime.now().isAfter(deadline)) {
          throw const FormatException(
            'Модель не успела загрузиться. Освободите оперативную память и повторите.',
          );
        }
        try {
          final health = await client
              .get(endpoint('/health'), headers: headers)
              .timeout(const Duration(seconds: 2));
          job.check();
          if (health.statusCode == 200) break;
        } catch (_) {
          job.check();
        }
        if (await channel.invokeMethod<bool>('running', {'id': id}) != true) {
          throw const FormatException(
            'Не удалось запустить локальную модель. Проверьте свободную память и целостность установки.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final fragments = (arguments['fragments'] as List).cast<String>();
      final schemas = (arguments['fragmentSchemas'] as List?)?.cast<String>();
      if (schemas != null && schemas.length != fragments.length) {
        throw const FormatException('Неверные границы рецептов в субтитрах.');
      }
      final outputs = <String>[];
      for (var index = 0; index < fragments.length; index++) {
        job.check();
        onProgress?.call(
          'Разбираю фрагмент ${index + 1} из ${fragments.length}…',
        );
        final response = await client
            .send(
              http.Request('POST', endpoint('/completion'))
                ..headers.addAll(headers)
                ..body = jsonEncode(
                  windowsCompletionBody(
                    arguments['instruction'] as String,
                    fragments[index],
                    schemas?[index] ?? arguments['schema'] as String,
                  ),
                ),
            )
            .timeout(requestTimeout);
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(requestTimeout)) {
          job.check();
          if (bytes.length + chunk.length > 256000) {
            throw const FormatException(
              'Локальная модель вернула слишком большой ответ.',
            );
          }
          bytes.addAll(chunk);
        }
        job.check();
        if (response.statusCode != 200) {
          throw const FormatException(
            'Локальная модель не завершила разбор. Исходный текст сохранён.',
          );
        }
        final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        // The shared decoder marks a truncated fragment for review, while
        // preserving valid earlier fragments and the complete original source.
        outputs.add(
          data['truncated'] == true ||
                  data['stop_type'] == 'limit' ||
                  data['stopped_limit'] == true
              ? ''
              : data['content'] as String,
        );
      }
      return {'outputs': outputs, 'backend': 'CPU'};
    } catch (_) {
      job.check();
      rethrow;
    } finally {
      unregister();
      client.close();
      await stop();
    }
  }
}
