import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/yandex_sync.dart';

void main() {
  test(
    'sync recovers another device even if the main file was overwritten',
    () async {
      final files = <String, String>{};
      final android = RecipeDatabase()
        ..put(const Recipe(id: 'a', title: 'Суп'), 'android');
      final windows = RecipeDatabase()
        ..put(const Recipe(id: 'b', title: 'Чай'), 'windows');
      files['/RecipeVault/recipes.json'] = android.encode();
      files['/RecipeVault/.devices/windows.json'] = windows.encode();
      final client = MockClient((request) async {
        final path =
            request.url.queryParameters['path'] ??
            request.url.queryParameters['file'];
        if (request.url.host == 'cloud-api.yandex.net') {
          expect(request.headers['Authorization'], 'OAuth secret');
          if (request.method == 'PUT') return http.Response('', 201);
          if (request.url.path.endsWith('/download')) {
            if (!files.containsKey(path)) return http.Response('', 404);
            return http.Response(
              jsonEncode({
                'href': Uri.https('transfer.example', '/download', {
                  'file': path!,
                }).toString(),
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/upload')) {
            return http.Response(
              jsonEncode({
                'href': Uri.https('transfer.example', '/upload', {
                  'file': path!,
                }).toString(),
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              '_embedded': {
                'total': files.keys
                    .where((k) => k.contains('/.devices/'))
                    .length,
                'items': files.keys
                    .where((k) => k.contains('/.devices/'))
                    .map(
                      (k) => {
                        'name': k.split('/').last,
                        'path': k,
                        'type': 'file',
                      },
                    )
                    .toList(),
              },
            }),
            200,
          );
        }
        expect(request.headers.containsKey('Authorization'), false);
        if (request.method == 'PUT') {
          files[path!] = utf8.decode(request.bodyBytes);
          return http.Response('', 201);
        }
        return http.Response(
          files[path]!,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final disk = YandexDisk(
        token: 'secret',
        folder: '/RecipeVault',
        client: client,
      );
      final merged = await disk.sync(android, 'android');
      expect(merged.recipes.map((r) => r.title).toSet(), {'Суп', 'Чай'});
      expect(
        RecipeDatabase.decode(
          files['/RecipeVault/recipes.json']!,
        ).recipes.length,
        2,
      );
      expect(
        RecipeDatabase.decode(
          files['/RecipeVault/.devices/android.json']!,
        ).recipes.length,
        2,
      );
    },
  );
  test('an authentication failure never writes the main database', () async {
    final client = MockClient((request) async => http.Response('', 401));
    final disk = YandexDisk(
      token: 'bad',
      folder: '/RecipeVault',
      client: client,
    );
    expect(
      disk.sync(RecipeDatabase(), 'android'),
      throwsA(isA<SyncException>()),
    );
  });
}
