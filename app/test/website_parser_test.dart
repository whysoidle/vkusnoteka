import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/services/website_parser.dart';

void main() {
  test('native website parsing extracts graph, sections and readable time', () {
    final data = {
      '@graph': [
        {
          '@type': 'Recipe',
          'name': 'Суп',
          'recipeIngredient': ['Вода — 1 л'],
          'totalTime': 'PT1H20M',
          'recipeInstructions': [
            {
              '@type': 'HowToSection',
              'itemListElement': [
                {'text': '<b>Вскипятите</b> воду.'},
              ],
            },
          ],
        },
      ],
    };
    final result = parseWebsite(
      '<script type="application/ld+json">${jsonEncode(data)}</script>',
      'https://example.com/soup',
    );
    expect(result.single.title, 'Суп');
    expect(result.single.steps, ['Вскипятите воду.']);
    expect(result.single.time, '1 ч 20 мин');
    expect(result.single.draft, false);
  });
  test(
    'native YouTube description parsing keeps video URL and literal amounts',
    () {
      final data = {
        'videoDetails': {
          'title': 'Сырники',
          'shortDescription':
              'Ингредиенты:\nТворог — 400 г\nПриготовление:\nОбжарьте.',
        },
      };
      final result = parseWebsite(
        '<script>var ytInitialPlayerResponse = ${jsonEncode(data)};</script>',
        'https://youtu.be/abcdefghijk',
      );
      expect(result.single.title, 'Сырники');
      expect(result.single.ingredients, ['Творог — 400 г']);
      expect(result.single.sourceUrl, 'https://youtu.be/abcdefghijk');
      expect(result.single.draft, false);
    },
  );
  test('an empty YouTube description yields an editable draft', () {
    final result = parseWebsite(
      '<title>Видео</title>',
      'https://youtu.be/abcdefghijk',
    );
    expect(result.single.sourceUrl, 'https://youtu.be/abcdefghijk');
    expect(result.single.draft, true);
  });
}
