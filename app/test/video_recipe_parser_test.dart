import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/services/recipe_ai_parser.dart';
import 'package:recipe_vault/services/video_recipe_parser.dart';

import 'fixtures/video_recipe_sample.dart';

Map<String, dynamic> steps(int index, List<int> evidence) => {
  'index': index,
  'steps': [
    {'evidence': evidence},
  ],
  'time': {'value': '', 'evidence': []},
  'servings': {'value': '', 'evidence': []},
  'warnings': [],
};

void main() {
  test(
    'distinct source measurements and ordinals constrain recipe selection',
    () {
      expect(
        videoFragmentRecipeIndexes(
          'Беру сто восемьдесят граммов муки.',
          outlines,
        ),
        [1],
      );
      expect(videoFragmentRecipeIndexes('Добавляю 250 г муки.', outlines), [2]);
      expect(
        videoFragmentRecipeIndexes('Перехожу ко второму рецепту.', outlines),
        [2],
      );
      expect(
        videoFragmentRecipeIndexes(
          'Добавляю 180 г, а во второй вариант 250 г.',
          outlines,
        ),
        [1, 2],
      );
      expect(videoFragmentRecipeIndexes('Разогреваю сковороду.', outlines), [
        1,
        2,
      ]);
    },
  );
  test('non-cooking outro is excluded before constrained step extraction', () {
    expect(
      videoCookingFragments('[9:00] Приятного аппетита! Подписывайтесь.'),
      isEmpty,
    );
    expect(
      videoCookingFragments('[0:20] Смешиваем яйца и добавляем муку.'),
      hasLength(1),
    );
  });
  test('multiple entries for the same recipe preserve all cooking actions', () {
    final result = decodeVideoSteps(
      [
        jsonEncode({
          'recipes': [
            steps(1, [1]),
            steps(1, [2]),
          ],
        }),
      ],
      ['Смешайте тесто.\nРазогрейте сковороду.'],
      outlines,
      source: 'Исходник',
      sourceUrl: 'url',
    );
    expect(result.recipes.first.steps.length, 2);
    expect(result.recipes.last.steps, isEmpty);
  });
  test('two published recipes keep separate, verbatim ingredient lists', () {
    expect(outlines.length, 2);
    expect(outlines.first.title, 'Рецепт теста на молоке');
    expect(outlines.first.ingredients, [
      'Молоко 400 мл',
      'Мука 180 граммов',
      'Яйца 2 штуки',
      'Масло 2 столовые ложки',
    ]);
    expect(outlines.last.title, 'Рецепт теста на воде');
    expect(outlines.last.ingredients.last, 'Соль по вкусу');
    expect(outlines.every((r) => r.draft), true);
    expect(
      outlines.expand((r) => r.ingredients).join(),
      isNot(contains('100')),
    );
  });

  test(
    'captions from different recipe phases do not contaminate each other',
    () {
      const first = '[0:20] Смешайте яйца с молоком.\n[0:30] Добавьте муку.';
      const second = '[3:00] Для второго теста смешайте яйца с водой.';
      final result = decodeVideoSteps(
        [
          jsonEncode({
            'recipes': [
              steps(1, [1, 2]),
            ],
          }),
          jsonEncode({
            'recipes': [
              steps(2, [1]),
            ],
          }),
        ],
        [first, second],
        outlines,
        source: '$description\n$first\n$second',
        sourceUrl: 'https://youtu.be/abcdefghijk',
      );
      expect(result.recipes.length, 2);
      expect(result.recipes.first.ingredients, outlines.first.ingredients);
      expect(result.recipes.last.ingredients, outlines.last.ingredients);
      expect(result.recipes.first.steps.single, contains('молоком'));
      expect(result.recipes.first.steps.join(), isNot(contains('водой')));
      expect(result.recipes.last.steps.single, contains('водой'));
      expect(result.recipes.every((r) => !r.draft), true);
      expect(
        result.recipes.every((r) => r.sourceUrl.contains('youtu.be')),
        true,
      );
    },
  );

  test(
    'missing or malformed fragment keeps confirmed products and a draft',
    () {
      final result = decodeVideoSteps(
        [
          jsonEncode({
            'recipes': [
              steps(1, [1]),
            ],
          }),
          '{truncated',
        ],
        ['Смешайте тесто.', 'Дайте тесту постоять.'],
        outlines,
        source: 'Исходник',
        sourceUrl: 'https://youtu.be/abcdefghijk',
      );
      expect(result.recipes.first.ingredients, outlines.first.ingredients);
      expect(result.recipes.last.ingredients, outlines.last.ingredients);
      expect(result.recipes.every((r) => r.draft), true);
      expect(result.warnings.join(), contains('фрагмент'));
    },
  );

  test('unmentioned recipes stay drafts and invalid recipe indexes fail', () {
    final result = decodeVideoSteps(
      ['{"recipes":[]}'],
      ['Привет, друзья!'],
      outlines,
      source: 'Привет, друзья!',
      sourceUrl: 'url',
    );
    expect(result.recipes.every((r) => r.steps.isEmpty && r.draft), true);
    expect(
      () => decodeVideoSteps(
        [
          jsonEncode({
            'recipes': [
              steps(99, [1]),
            ],
          }),
        ],
        ['Смешайте.'],
        outlines,
        source: 'Смешайте.',
        sourceUrl: 'url',
      ),
      throwsFormatException,
    );
  });

  test(
    'automatic caption rows form coherent, evidence-addressable passages',
    () {
      final captions = [
        '[0:00] Для теста беру',
        '[0:02] двести граммов',
        '[0:04] муки и добавляю',
        '[0:06] молоко небольшими порциями',
        '[0:08] затем хорошо',
        '[0:10] перемешиваю венчиком',
        '[0:22] Теперь ставлю сковороду',
        '[0:24] на плиту и нагреваю',
      ].join('\n');
      final lines = sourceLines(captions);
      expect(lines.length, 2);
      expect(lines.first, contains('беру двести граммов муки'));
      expect(lines.first, startsWith('[0:00]'));
      expect(lines.last, startsWith('[0:22]'));
      final numbered = numberedTranscript(captions);
      expect(numbered, contains('[1] Для теста беру двести граммов муки'));
      expect(numbered, contains('[2] Теперь ставлю сковороду'));
      expect(numbered, isNot(contains('[0:00]')));
    },
  );
}
