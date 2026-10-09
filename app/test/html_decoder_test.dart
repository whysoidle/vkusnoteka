import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_vault/services/html_decoder.dart';
import 'package:recipe_vault/services/import_service.dart';

void main() {
  final page = File('test/fixtures/russianfood_cp1251.html').readAsBytesSync();
  test('HTTP Windows-1251 charset restores actual Cyrillic byte values', () {
    expect(
      decodeHtml([
        0xcf,
        0xf0,
        0xe8,
        0xe2,
        0xe5,
        0xf2,
        0x20,
        0xa8,
        0xb8,
      ], contentType: 'text/html; CHARSET="windows-1251"'),
      'Привет Ёё',
    );
  });
  test(
    'HTML meta declares Windows-1251 when the HTTP header omits charset',
    () {
      final decoded = decodeHtml(page, contentType: 'text/html');
      expect(decoded, contains('Макароны с сыром'));
      expect(decoded, isNot(contains('\ufffd')));
    },
  );
  test('modern charset meta and common alias cp1251 are recognized', () {
    final bytes = [
      ...ascii.encode('<meta charset="cp1251"><p>'),
      0xd1,
      0xfb,
      0xf0,
      ...ascii.encode('</p>'),
    ];
    expect(decodeHtml(bytes), contains('Сыр'));
  });
  test('HTTP charset takes precedence over a conflicting HTML meta', () {
    final decoded = decodeHtml(
      utf8.encode('<meta charset="windows-1251"><p>Сыр 🧀</p>'),
      contentType: 'text/html; charset=utf-8',
    );
    expect(decoded, contains('Сыр 🧀'));
  });
  test('UTF-8 BOM takes precedence over stale charset declarations', () {
    expect(
      decodeHtml([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('Сыр 🧀'),
      ], contentType: 'text/html; charset=windows-1251'),
      'Сыр 🧀',
    );
  });
  test('UTF-16 BOM is decoded before the HTML metadata scan', () {
    expect(decodeHtml([0xff, 0xfe, 0x21, 0x04, 0x4b, 0x04, 0x40, 0x04]), 'Сыр');
  });
  test('unmarked UTF-8 keeps Cyrillic and emoji unchanged', () {
    expect(decodeHtml(utf8.encode('Рецепт 🥣')), 'Рецепт 🥣');
  });
  test(
    'charset declarations in comments do not override document encoding',
    () {
      expect(
        decodeHtml(
          utf8.encode('<!-- <meta charset="windows-1251"> --><p>Сыр</p>'),
        ),
        contains('<p>Сыр</p>'),
      );
    },
  );
  test('bad UTF-8 is rejected rather than permanently replacing letters', () {
    expect(() => decodeHtml([0xff, 0xff]), throwsFormatException);
  });
  for (final header in ['text/html; charset=windows-1251', 'text/html']) {
    test('full native import supports RussianFood with $header', () async {
      final importer = ImportService(
        client: MockClient(
          (_) async =>
              http.Response.bytes(page, 200, headers: {'content-type': header}),
        ),
      );
      addTearDown(importer.client.close);
      const url = 'https://www.russianfood.com/recipes/recipe.php?rid=161091';
      final recipe = (await importer.parse(url, server: '')).recipes.single;
      expect(recipe.title, 'Макароны с сыром');
      expect(recipe.ingredients, ['Макароны — 200 г', 'Сыр — 100 г']);
      expect(recipe.steps, ['Отварите макароны.', 'Добавьте сыр.']);
      expect(recipe.servings, 'на 3 порции');
      expect(recipe.sourceUrl, url);
      expect(recipe.draft, false);
      expect(jsonEncode(recipe.toJson()), isNot(contains('\ufffd')));
    });
  }
}
