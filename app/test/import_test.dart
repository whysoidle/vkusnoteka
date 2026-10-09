import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/services/import_service.dart';

void main() {
  test(
    'without server a YouTube link is a draft retaining the exact URL',
    () async {
      final result = await ImportService(
        client: MockClient((_) async => http.Response('', 404)),
      ).parse('https://youtu.be/abcdefghijk?t=10', server: '');
      expect(
        result.recipes.single.sourceUrl,
        'https://youtu.be/abcdefghijk?t=10',
      );
      expect(result.recipes.single.draft, true);
    },
  );
  test('upstream cannot accidentally drop the source link', () async {
    final service = ImportService(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer abc');
        return http.Response(
          jsonEncode({
            'recipes': [
              {
                'title': 'Суп',
                'ingredients': ['Вода'],
                'steps': ['Сварить.'],
                'draft': false,
              },
            ],
            'warnings': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await service.parse(
      'https://example.com/recipe',
      server: 'https://import.example.com/',
      token: 'abc',
    );
    expect(result.recipes.single.sourceUrl, 'https://example.com/recipe');
  });
}
