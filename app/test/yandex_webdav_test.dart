import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/yandex_sync.dart';
import 'package:recipe_vault/services/yandex_webdav.dart';

String resource(
  String href, {
  bool collection = false,
  String status = '200 OK',
}) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
    '<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>'
    '</d:prop><d:status>HTTP/1.1 $status</d:status></d:propstat></d:response>';
http.Response listing(Iterable<String> resources) => http.Response(
  '<d:multistatus xmlns:d="DAV:">${resources.join()}</d:multistatus>',
  207,
  headers: {'content-type': 'application/xml; charset=utf-8'},
);

class FakeWebDav {
  final files = <String, String>{};
  final folders = <String>{'/'};
  final methods = <String>[];
  int? rejectMove;
  late final client = MockClient((request) async {
    expect(request.url.origin, 'https://webdav.yandex.ru');
    expect(request.followRedirects, false);
    expect(
      request.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('test:app-password'))}',
    );
    final path =
        '/${request.url.pathSegments.where((part) => part.isNotEmpty).join('/')}';
    methods.add('${request.method} $path');
    switch (request.method) {
      case 'MKCOL':
        if (folders.contains(path) || files.containsKey(path)) {
          return http.Response('', 405);
        }
        folders.add(path);
        return http.Response('', 201);
      case 'PROPFIND':
        if (!folders.contains(path) && !files.containsKey(path)) {
          return http.Response('', 404);
        }
        return listing([
          resource(request.url.path, collection: folders.contains(path)),
          if (request.headers['Depth'] == '1')
            for (final file in files.keys.where(
              (file) =>
                  file.startsWith('$path/') &&
                  !file.substring(path.length + 1).contains('/'),
            ))
              resource(Uri(path: file).toString()),
        ]);
      case 'GET':
        return files.containsKey(path)
            ? http.Response(
                files[path]!,
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response('', 404);
      case 'PUT':
        expect(path.endsWith('.upload'), true);
        files[path] = utf8.decode(request.bodyBytes);
        return http.Response('', 201);
      case 'MOVE':
        if (rejectMove != null) return http.Response('', rejectMove!);
        final target = Uri.parse(request.headers['Destination']!);
        expect(target.origin, request.url.origin);
        expect(request.headers['Overwrite'], 'T');
        final dest = '/${target.pathSegments.join('/')}';
        files[dest] = files.remove(path)!;
        return http.Response('', 204);
      default:
        fail('Unexpected method ${request.method}');
    }
  });
  YandexWebDav disk({String folder = '/RecipeVault'}) => YandexWebDav(
    login: 'test',
    password: 'app-password',
    folder: folder,
    client: client,
  );
}

void main() {
  test(
    'sync preserves Cyrillic, recovers both devices and converges with deletions',
    () async {
      final server = FakeWebDav();
      final android = RecipeDatabase()
        ..put(const Recipe(id: 'a', title: 'Суп'), 'android');
      final windows = RecipeDatabase()
        ..put(const Recipe(id: 'b', title: 'Чай'), 'windows');
      server.files['/RecipeVault/recipes.json'] = android.encode();
      server.files['/RecipeVault/.devices/windows.json'] = windows.encode();
      final first = await server.disk().sync(android, 'android');
      expect(first.recipes.map((r) => r.title).toSet(), {'Суп', 'Чай'});
      final next = await server.disk().sync(windows, 'windows');
      next.remove('a', 'windows');
      await server.disk().sync(next, 'windows');
      final merged = await server.disk().sync(first, 'android');
      expect(merged.recipes.map((r) => r.title), ['Чай']);
      expect(
        RecipeDatabase.decode(
          server.files['/RecipeVault/recipes.json']!,
        ).encode(),
        merged.encode(),
      );
      expect(server.files.keys.any((path) => path.endsWith('.upload')), false);
    },
  );
  test(
    'existing folder uses MKCOL 405 and verifies it is a collection',
    () async {
      final server = FakeWebDav()..folders.add('/RecipeVault');
      await server.disk().mkdir('/RecipeVault');
      expect(server.methods, ['MKCOL /RecipeVault', 'PROPFIND /RecipeVault']);
      server.files['/occupied'] = 'not a directory';
      await expectLater(
        server.disk().mkdir('/occupied'),
        throwsA(isA<SyncException>()),
      );
    },
  );
  test('connection check is read only and never replaces recipes', () async {
    final server = FakeWebDav();
    await server.disk().checkConnection();
    expect(server.methods, ['PROPFIND /']);
    expect(server.files, isEmpty);
  });
  test('failed MOVE leaves existing main database intact', () async {
    final server = FakeWebDav()..rejectMove = 507;
    server.files['/RecipeVault/recipes.json'] = 'old';
    await expectLater(
      server.disk().upload('/RecipeVault/recipes.json', RecipeDatabase()),
      throwsA(isA<SyncException>()),
    );
    expect(server.files['/RecipeVault/recipes.json'], 'old');
    expect(
      server.methods.any((method) => method == 'PUT /RecipeVault/recipes.json'),
      false,
    );
  });
  test('a corrupt main database is never overwritten', () async {
    final server = FakeWebDav();
    server.files['/RecipeVault/recipes.json'] = 'invalid JSON';
    await expectLater(
      server.disk().sync(RecipeDatabase(), 'android'),
      throwsA(isA<SyncException>()),
    );
    expect(server.files['/RecipeVault/recipes.json'], 'invalid JSON');
  });
  for (final status in [401, 403, 429, 507, 302, 503]) {
    test('HTTP $status gives an actionable error without writes', () async {
      final calls = <String>[];
      final disk = YandexWebDav(
        login: 'test',
        password: 'app-password',
        folder: '/RecipeVault',
        client: MockClient((request) async {
          calls.add(request.method);
          return http.Response(
            '',
            status,
            headers: {'location': 'https://elsewhere.example'},
          );
        }),
      );
      await expectLater(disk.checkConnection(), throwsA(isA<SyncException>()));
      expect(calls, ['PROPFIND']);
    });
  }
  test(
    'names with spaces, Cyrillic and URL characters are correctly encoded',
    () async {
      final server = FakeWebDav();
      const folder = '/Мои рецепты/Супы #1';
      await server.disk(folder: folder).sync(RecipeDatabase(), 'android');
      expect(server.files.containsKey('$folder/recipes.json'), true);
      expect(server.methods.any((method) => method.contains(folder)), true);
    },
  );
  test(
    'listing handles different DAV prefixes and ignores unfinished uploads',
    () async {
      final body =
          '<multistatus xmlns="DAV:">${resource('/RecipeVault/.devices/', collection: true)}${resource('https://webdav.yandex.ru/RecipeVault/.devices/windows.json')}${resource('/RecipeVault/.devices/tmp.upload')}</multistatus>'
              .replaceAll('<d:', '<')
              .replaceAll('</d:', '</');
      final disk = YandexWebDav(
        login: 'test',
        password: 'app-password',
        folder: '/RecipeVault',
        client: MockClient((request) async => http.Response(body, 207)),
      );
      expect(await disk.replicas(), ['/RecipeVault/.devices/windows.json']);
    },
  );
  for (final href in [
    'https://other.example/RecipeVault/.devices/a.json',
    '/other/a.json',
    '/RecipeVault/.devices/a%2Fb.json',
  ]) {
    test('rejects unsafe or out of folder listing href $href', () async {
      final disk = YandexWebDav(
        login: 'test',
        password: 'app-password',
        folder: '/RecipeVault',
        client: MockClient(
          (request) async => listing([
            resource('/RecipeVault/.devices/', collection: true),
            resource(href),
          ]),
        ),
      );
      await expectLater(disk.replicas(), throwsA(isA<SyncException>()));
    });
  }
  test(
    'bad or partially denied listing never silently drops a device',
    () async {
      for (final response in [
        http.Response('<html/>', 207),
        listing([
          resource('/RecipeVault/.devices/', collection: true),
          resource('/RecipeVault/.devices/a.json', status: '403 Forbidden'),
        ]),
        listing([]),
      ]) {
        final disk = YandexWebDav(
          login: 'test',
          password: 'app-password',
          folder: '/RecipeVault',
          client: MockClient((request) async => response),
        );
        await expectLater(disk.replicas(), throwsA(isA<SyncException>()));
      }
    },
  );
  test('download enforces the database size limit before decoding', () async {
    final disk = YandexWebDav(
      login: 'test',
      password: 'app-password',
      folder: '/RecipeVault',
      client: MockClient(
        (request) async => http.Response('x' * (20 * 1024 * 1024 + 1), 200),
      ),
    );
    await expectLater(
      disk.download('/RecipeVault/recipes.json'),
      throwsA(isA<SyncException>()),
    );
  });
  test(
    'missing credentials and unsafe device IDs do not send requests',
    () async {
      var calls = 0;
      final disk = YandexWebDav(
        login: '',
        password: '',
        folder: '/RecipeVault',
        client: MockClient((request) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      await expectLater(disk.checkConnection(), throwsA(isA<SyncException>()));
      final server = FakeWebDav();
      await expectLater(
        server.disk().sync(RecipeDatabase(), '../outside'),
        throwsA(isA<SyncException>()),
      );
      expect(calls, 0);
      expect(server.methods, isEmpty);
    },
  );
}
