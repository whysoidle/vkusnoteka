import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';

class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

abstract class RecipeCloudStore {
  final String folder;
  final http.Client client;
  RecipeCloudStore({required String folder, http.Client? client})
    : folder = folder.replaceAll(RegExp(r'/+$'), ''),
      client = client ?? http.Client();
  bool get hasCredentials;
  Future<void> mkdir(String path);
  Future<RecipeDatabase?> download(String path);
  Future<void> upload(String path, RecipeDatabase database);
  Future<List<String>> replicas();

  /// A single main database plus one recovery replica per device guarantees eventual
  /// convergence even though Yandex upload has no compare-and-swap operation.
  Future<RecipeDatabase> sync(RecipeDatabase local, String deviceId) async {
    if (!hasCredentials) {
      throw const SyncException('Подключите Яндекс Диск в настройках.');
    }
    if (!folder.startsWith('/') ||
        folder == '/' ||
        folder.contains('..') ||
        folder.contains('\\') ||
        RegExp(r'[\x00-\x1f]').hasMatch(folder)) {
      throw const SyncException(
        'Укажите отдельную папку, например /RecipeVault.',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(deviceId)) {
      throw const SyncException('Некорректный идентификатор устройства.');
    }
    var current = '';
    for (final part in folder.split('/').where((part) => part.isNotEmpty)) {
      current += '/$part';
      await mkdir(current);
    }
    await mkdir('$folder/.devices');
    final ownPath = '$folder/.devices/$deviceId.json';
    // Persist this device's previous upload before replacing it, e.g. after local recovery.
    var merged = local;
    final own = await download(ownPath);
    if (own != null) merged = mergeDatabases(merged, own);
    await upload(ownPath, merged);
    final main = await download('$folder/recipes.json');
    if (main != null) merged = mergeDatabases(merged, main);
    for (final path in await replicas()) {
      final remote = await download(path);
      if (remote != null) merged = mergeDatabases(merged, remote);
    }
    await upload(ownPath, merged);
    await upload('$folder/recipes.json', merged);
    return merged;
  }
}

class YandexDisk extends RecipeCloudStore {
  final String token;
  YandexDisk({required this.token, required super.folder, super.client});
  @override
  bool get hasCredentials => token.isNotEmpty;
  static const api = 'https://cloud-api.yandex.net/v1/disk';
  Map<String, String> get headers => {'Authorization': 'OAuth $token'};
  Uri endpoint(String route, Map<String, String> params) =>
      Uri.parse('$api$route').replace(queryParameters: params);
  void check(
    http.Response response, {
    Set<int> allowed = const {200, 201, 202, 204},
  }) {
    if (allowed.contains(response.statusCode)) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SyncException(
        'Нет доступа к Яндекс Диску. Повторите вход и проверьте разрешения на чтение и запись.',
      );
    }
    if (response.statusCode == 507) {
      throw const SyncException('На Яндекс Диске закончилось место.');
    }
    throw SyncException(
      'Яндекс Диск вернул ошибку ${response.statusCode}. Локальная база сохранена.',
    );
  }

  @override
  Future<void> mkdir(String path) async {
    final response = await client
        .put(endpoint('/resources', {'path': path}), headers: headers)
        .timeout(const Duration(seconds: 30));
    check(response, allowed: {201, 409});
    if (response.statusCode == 409) {
      final existing = await client
          .get(endpoint('/resources', {'path': path}), headers: headers)
          .timeout(const Duration(seconds: 30));
      check(existing);
      if ((jsonDecode(existing.body) as Map)['type'] != 'dir') {
        throw const SyncException('Путь базы занят файлом. Выберите папку.');
      }
    }
  }

  Uri signedLink(String body) {
    final link = Uri.parse((jsonDecode(body) as Map)['href'] as String);
    if (link.scheme != 'https') {
      throw const SyncException('Яндекс Диск вернул небезопасный адрес.');
    }
    return link;
  }

  @override
  Future<RecipeDatabase?> download(String path) async {
    final response = await client
        .get(endpoint('/resources/download', {'path': path}), headers: headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return null;
    check(response);
    final file = await client
        .get(signedLink(response.body))
        .timeout(const Duration(seconds: 45));
    check(file);
    if (file.bodyBytes.length > 20 * 1024 * 1024) {
      throw const SyncException(
        'База превышает 20 МБ. Синхронизация остановлена.',
      );
    }
    return RecipeDatabase.decode(utf8.decode(file.bodyBytes));
  }

  @override
  Future<void> upload(String path, RecipeDatabase database) async {
    final body = utf8.encode(database.encode());
    if (body.length > 20 * 1024 * 1024) {
      throw const SyncException(
        'База превышает 20 МБ. Сократите исходные тексты.',
      );
    }
    final response = await client
        .get(
          endpoint('/resources/upload', {'path': path, 'overwrite': 'true'}),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
    check(response);
    final result = await client
        .put(
          signedLink(response.body),
          body: body,
          headers: {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(seconds: 45));
    check(result);
  }

  @override
  Future<List<String>> replicas() async {
    final paths = <String>[];
    var offset = 0;
    while (true) {
      final response = await client
          .get(
            endpoint('/resources', {
              'path': '$folder/.devices',
              'limit': '100',
              'offset': '$offset',
            }),
            headers: headers,
          )
          .timeout(const Duration(seconds: 30));
      check(response);
      final embedded = (jsonDecode(response.body) as Map)['_embedded'] as Map;
      final items = embedded['items'] as List;
      paths.addAll(
        items
            .where(
              (e) =>
                  e['type'] == 'file' &&
                  (e['name'] as String).endsWith('.json'),
            )
            .map((e) => e['path'] as String),
      );
      offset += items.length;
      if (items.isEmpty || offset >= (embedded['total'] as int)) break;
    }
    return paths;
  }
}
