import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import '../models/recipe.dart';
import 'yandex_sync.dart';

/// Credentials are sent only to this fixed HTTPS origin. Redirects are rejected.
class YandexWebDav extends RecipeCloudStore {
  final String login, password;
  YandexWebDav({
    required this.login,
    required this.password,
    required super.folder,
    super.client,
  });
  static final origin = Uri.parse('https://webdav.yandex.ru');
  static const maxDatabaseBytes = 20 * 1024 * 1024;
  @override
  bool get hasCredentials =>
      login.trim().isNotEmpty && password.trim().isNotEmpty;
  Uri endpoint(String path) => path == '/'
      ? origin.replace(path: '/')
      : origin.replace(
          pathSegments: [
            ...path.split('/').where((part) => part.isNotEmpty),
            if (path.endsWith('/')) '',
          ],
        );

  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
    int maxBytes = maxDatabaseBytes,
  }) async {
    if (!hasCredentials ||
        login.contains(':') ||
        RegExp(r'[\x00-\x1f]').hasMatch(login)) {
      throw const SyncException(
        'Укажите логин Яндекса и пароль приложения «Файлы WebDAV».',
      );
    }
    final request = http.Request(method, endpoint(path))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${login.trim()}:${password.trim()}'))}',
        ...headers,
      });
    if (body != null) request.bodyBytes = body;
    return (() async {
      final response = await client.send(request);
      if (response.contentLength != null &&
          response.contentLength! > maxBytes) {
        throw const SyncException(
          'Ответ Яндекс Диска превышает допустимый размер. Синхронизация остановлена.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const SyncException(
            'Ответ Яндекс Диска превышает допустимый размер. Синхронизация остановлена.',
          );
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      );
    })().timeout(const Duration(seconds: 45));
  }

  void check(http.Response response, Set<int> allowed) {
    if (allowed.contains(response.statusCode)) return;
    switch (response.statusCode) {
      case 401:
        throw const SyncException(
          'Проверьте логин и пароль приложения «Файлы WebDAV». Обычный пароль Яндекса не подходит.',
        );
      case 402:
      case 403:
        throw const SyncException(
          'Яндекс запретил доступ по WebDAV. Проверьте пароль приложения и наличие тарифа Яндекс 360 с поддержкой WebDAV.',
        );
      case 507:
        throw const SyncException('На Яндекс Диске закончилось место.');
      case 429:
        throw const SyncException(
          'Яндекс Диск временно ограничил запросы. Повторите синхронизацию позже.',
        );
      default:
        throw SyncException(
          'Ошибка WebDAV ${response.statusCode}. Локальные рецепты сохранены; повторите попытку.',
        );
    }
  }

  Future<http.Response> properties(String path, String depth) => request(
    'PROPFIND',
    path,
    headers: {'Depth': depth, 'Content-Type': 'application/xml; charset=utf-8'},
    body: utf8.encode(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>',
    ),
    maxBytes: 2 * 1024 * 1024,
  );

  Iterable<XmlElement> children(XmlElement element, String name) => element
      .children
      .whereType<XmlElement>()
      .where((e) => e.name.local == name && e.namespaceUri == 'DAV:');
  XmlElement singleChild(XmlElement element, String name) {
    final matches = children(element, name).toList();
    if (matches.length != 1) {
      throw const FormatException('Invalid WebDAV property');
    }
    return matches.single;
  }

  List<({String path, bool collection})> entries(http.Response response) {
    check(response, {207});
    try {
      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      final root = document.rootElement;
      if (root.name.local != 'multistatus' || root.namespaceUri != 'DAV:') {
        throw const FormatException('Invalid multistatus');
      }
      final result = <({String path, bool collection})>[];
      for (final entry in children(root, 'response')) {
        final href = singleChild(entry, 'href').innerText.trim();
        final uri = origin.resolve(href);
        if (href.isEmpty ||
            uri.scheme != origin.scheme ||
            uri.host != origin.host ||
            uri.port != origin.port ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw const FormatException('Invalid WebDAV href');
        }
        XmlElement? resource;
        for (final propstat in children(entry, 'propstat')) {
          if (RegExp(
            r'^HTTP/\S+ 200(?:\s|$)',
          ).hasMatch(singleChild(propstat, 'status').innerText.trim())) {
            final prop = singleChild(propstat, 'prop');
            final types = children(prop, 'resourcetype');
            if (types.isNotEmpty) resource = types.single;
          }
        }
        if (resource == null) {
          throw const FormatException('Missing resource type');
        }
        final parts = uri.pathSegments
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\'),
        )) {
          throw const FormatException('Invalid WebDAV path');
        }
        result.add((
          path: '/${parts.join('/')}',
          collection: children(resource, 'collection').isNotEmpty,
        ));
      }
      return result;
    } catch (_) {
      throw const SyncException(
        'Не удалось прочитать список файлов WebDAV. Облачная база не заменена.',
      );
    }
  }

  Future<void> checkConnection() async {
    final root = entries(await properties('/', '0'));
    if (!root.any((e) => e.path == '/' && e.collection)) {
      throw const SyncException(
        'Сервер WebDAV не подтвердил доступ к Яндекс Диску.',
      );
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final response = await request('MKCOL', path, maxBytes: 1024 * 1024);
    check(response, {201, 405});
    if (response.statusCode == 405) {
      final existing = entries(await properties(path, '0'));
      if (!existing.any((entry) => entry.path == path && entry.collection)) {
        throw const SyncException(
          'Путь базы занят файлом. Выберите другую папку.',
        );
      }
    }
  }

  @override
  Future<RecipeDatabase?> download(String path) async {
    final response = await request('GET', path);
    if (response.statusCode == 404) return null;
    check(response, {200});
    try {
      return RecipeDatabase.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const SyncException(
        'Облачный файл рецептов повреждён или имеет неизвестный формат. Он не заменён; локальная база сохранена.',
      );
    }
  }

  @override
  Future<void> upload(String path, RecipeDatabase database) async {
    final body = utf8.encode(database.encode());
    if (body.length > maxDatabaseBytes) {
      throw const SyncException(
        'База превышает 20 МБ. Сократите исходные тексты и фотографии.',
      );
    }
    // Publish only a fully uploaded file; an interrupted PUT cannot damage the main database.
    final pending = '$path.${const Uuid().v4()}.upload';
    check(
      await request(
        'PUT',
        pending,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      ),
      {201, 204},
    );
    check(
      await request(
        'MOVE',
        pending,
        headers: {'Destination': endpoint(path).toString(), 'Overwrite': 'T'},
      ),
      {201, 204},
    );
  }

  @override
  Future<List<String>> replicas() async {
    final base = '$folder/.devices';
    final result = <String>{};
    final listing = entries(await properties('$base/', '1'));
    if (!listing.any((entry) => entry.path == base && entry.collection)) {
      throw const SyncException(
        'Сервер вернул неполный список копий устройств. Повторите синхронизацию.',
      );
    }
    for (final entry in listing) {
      if (entry.path == base) continue;
      if (!entry.path.startsWith('$base/') ||
          entry.path.substring(base.length + 1).contains('/')) {
        throw const SyncException(
          'WebDAV вернул файл за пределами папки базы. Синхронизация остановлена.',
        );
      }
      if (!entry.collection && entry.path.endsWith('.json')) {
        result.add(entry.path);
      }
    }
    if (result.length > 1000) {
      throw const SyncException(
        'Слишком много копий устройств в папке базы. Синхронизация остановлена.',
      );
    }
    return result.toList();
  }
}
