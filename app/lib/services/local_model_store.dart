import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'import_job.dart';

class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);
  @override
  String toString() => message;
}

void _hashModel(List<Object> arguments) async {
  final path = arguments[0] as String;
  final port = arguments[1] as SendPort;
  try {
    port.send((await sha256.bind(File(path).openRead()).first).toString());
  } catch (_) {
    port.send(null);
  }
}

Future<String> _modelHash(String path, ImportJob job) async {
  final port = ReceivePort();
  final answer = Completer<String>();
  final subscription = port.listen((value) {
    if (answer.isCompleted) return;
    if (value is String) {
      answer.complete(value);
    } else {
      answer.completeError(
        const ModelDownloadException('Не удалось проверить файл модели.'),
      );
    }
  });
  Isolate? isolate;
  void Function()? unregister;
  try {
    isolate = await Isolate.spawn(_hashModel, [path, port.sendPort]);
    unregister = job.onCancel(() {
      isolate?.kill(priority: Isolate.immediate);
      if (!answer.isCompleted) answer.completeError(const ImportCancelled());
    });
    return await answer.future;
  } finally {
    unregister?.call();
    isolate?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}

/// A pinned, public conversion; weights never enter recipes.json.
class LocalModelStore {
  static const name = 'Qwen3 1.7B INT4';
  static const size = 977184032;
  static const checksum =
      '2eeffef7b51bc3e1225ea69fe7aa5f417397934b56a5b6c20cc068d6fd2c918b';
  static const downloadUrl =
      'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/'
      '73fbc3fe8271c162a603ee66f6e7ed25b6211195/'
      'Qwen3-1.7B_dynamic_wi4b32_afp32.litertlm';
  final Directory directory;
  final Uri url;
  final int expectedSize;
  final String expectedChecksum;
  LocalModelStore(
    this.directory, {
    Uri? url,
    this.expectedSize = size,
    this.expectedChecksum = checksum,
  }) : url = url ?? Uri.parse(downloadUrl);

  static Future<LocalModelStore> open() async => LocalModelStore(
    Directory(p.join((await getApplicationSupportDirectory()).path, 'LocalAI')),
  );
  File get file => File(p.join(directory.path, 'qwen-recipe.litertlm'));
  File get partial => File('${file.path}.part');
  Future<bool> get ready async =>
      await file.exists() && await file.length() == expectedSize;

  Future<void> remove() async {
    for (final f in [file, partial]) {
      if (await f.exists()) await f.delete();
    }
  }

  Future<void> download({
    required ImportJob job,
    required void Function(int received, int total) onProgress,
    http.Client? client,
  }) async {
    await directory.create(recursive: true);
    job.check();
    if (await ready) {
      if (await partial.exists()) await partial.delete();
      onProgress(expectedSize, expectedSize);
      return;
    }
    // Remove obsolete weights before downloading a replacement.
    if (await file.exists()) await file.delete();
    final network = client ?? http.Client();
    final unregister = job.onCancel(network.close);
    IOSink? sink;
    try {
      var received = await partial.exists() ? await partial.length() : 0;
      if (received > expectedSize) {
        await partial.delete();
        received = 0;
      }
      onProgress(received, expectedSize);
      if (received < expectedSize) {
        final request = http.Request('GET', url);
        if (received > 0) request.headers['Range'] = 'bytes=$received-';
        final response = await network
            .send(request)
            .timeout(const Duration(seconds: 35));
        job.check();
        if (response.statusCode == 206) {
          final range = response.headers['content-range'];
          if (range != 'bytes $received-${expectedSize - 1}/$expectedSize') {
            throw const ModelDownloadException(
              'Сервер вернул неверную часть модели. Повторите загрузку.',
            );
          }
        } else if (response.statusCode == 200) {
          received = 0;
        } else {
          throw const ModelDownloadException(
            'Модель недоступна для скачивания. Проверьте интернет и повторите.',
          );
        }
        if (response.contentLength != null &&
            response.contentLength != expectedSize - received) {
          throw const ModelDownloadException(
            'Размер загрузки не совпадает с моделью.',
          );
        }
        sink = partial.openWrite(
          mode: received == 0 ? FileMode.write : FileMode.append,
        );
        await sink.addStream(
          response.stream.timeout(const Duration(seconds: 60)).map((chunk) {
            job.check();
            received += chunk.length;
            if (received > expectedSize) {
              throw const ModelDownloadException(
                'Сервер прислал слишком большой файл.',
              );
            }
            onProgress(received, expectedSize);
            return chunk;
          }),
        );
        await sink.flush();
        await sink.close();
        sink = null;
      }
      job.check();
      if (await partial.length() != expectedSize) {
        throw const ModelDownloadException(
          'Загрузка оборвалась. Нажмите «Скачать», чтобы продолжить.',
        );
      }
      final path = partial.path;
      final hash = await _modelHash(path, job);
      job.check();
      if (hash != expectedChecksum) {
        await partial.delete();
        throw const ModelDownloadException(
          'Проверка модели не прошла. Скачайте её повторно.',
        );
      }
      await partial.rename(file.path);
    } catch (_) {
      job.check();
      rethrow;
    } finally {
      unregister();
      try {
        await sink?.close();
      } finally {
        network.close();
      }
    }
  }
}
