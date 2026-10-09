import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/services/local_recipe_ai.dart';
import 'package:recipe_vault/services/storage.dart';

const source =
    '[0:12] Берём 200 г муки и молоко.\n[0:20] Смешайте муку с молоком.';
Map<String, dynamic> answer() => {
  'title': 'Тесто',
  'ingredients': [
    {'name': 'Мука', 'quantity': '200 г', 'evidence': 'Берём 200 г муки'},
    {'name': 'Молоко', 'quantity': '', 'evidence': 'муки и молоко'},
  ],
  'steps': [
    {
      'text': '[0:20] Смешайте муку с молоком.',
      'evidence': 'Смешайте муку с молоком.',
    },
  ],
  'time': {'value': '', 'evidence': ''},
  'servings': {'value': '', 'evidence': ''},
  'warnings': [],
};
LocalAiResult decode(List<String> outputs, List<String> fragments) =>
    decodeAiRecipes(
      outputs,
      fragments,
      source: source,
      sourceUrl: 'https://youtu.be/abcdefghijk?t=12',
      fallbackTitle: 'Видео',
    );

void main() {
  test(
    'quantities on a shared source line cannot be borrowed from another ingredient',
    () {
      final data = answer();
      data['ingredients'] = [
        {
          'name': 'Мука',
          'quantity': '300 мл',
          'evidence': [1],
        },
        {
          'name': 'Молоко',
          'quantity': '200 г',
          'evidence': [1],
        },
      ];
      data['steps'] = [];
      final result = decode(
        [jsonEncode(data)],
        ['Берём 200 г муки и 300 мл молока.'],
      );
      expect(result.recipe.ingredients, [
        'Мука — количество не указано',
        'Молоко — количество не указано',
      ]);
      data['ingredients'] = [
        {
          'name': 'Мука',
          'quantity': '200 г',
          'evidence': [1],
        },
        {
          'name': 'Молоко',
          'quantity': '300 мл',
          'evidence': [1],
        },
      ];
      final corrected = decode(
        [jsonEncode(data)],
        ['Берём 200 г муки и 300 мл молока.'],
      );
      expect(corrected.recipe.ingredients, ['Мука — 200 г', 'Молоко — 300 мл']);
    },
  );
  test('a piece count must be next to that ingredient in the source', () {
    final data = answer();
    data['ingredients'] = [
      {
        'name': 'Яйцо',
        'quantity': '3 шт.',
        'evidence': [1],
      },
    ];
    data['steps'] = [];
    final result = decode(
      [jsonEncode(data)],
      ['Разбейте яйцо и перемешивайте 3 минуты.'],
    );
    expect(result.recipe.ingredients.single, 'Яйцо — количество не указано');
  });
  test('a cited line does not authorize an absent ingredient or a utensil', () {
    final data = answer();
    data['ingredients'] = [
      {
        'name': 'Вода',
        'quantity': '200 г',
        'evidence': [1],
      },
      {
        'name': 'Сковорода',
        'quantity': '',
        'evidence': [2],
      },
      {
        'name': 'Мука',
        'quantity': '200 г',
        'evidence': [1],
      },
    ];
    data['steps'] = [];
    final result = decode(
      [jsonEncode(data)],
      ['Берём 200 г муки.\nРазогрейте сковороду.'],
    );
    expect(result.recipe.ingredients, ['Мука — 200 г']);
    expect(result.recipe.draft, true);
  });
  test('spoken quantities and full unit names survive evidence checks', () {
    final data = answer();
    data['ingredients'] = [
      {
        'name': 'Мука',
        'quantity': '250 г',
        'evidence': [1],
      },
      {
        'name': 'Сахар',
        'quantity': '2 ст. л.',
        'evidence': [2],
      },
      {
        'name': 'Яйцо',
        'quantity': '3',
        'evidence': [3],
      },
    ];
    data['steps'] = [];
    final result = decode(
      [jsonEncode(data)],
      [
        'Берём двести пятьдесят граммов муки.\n'
            'Добавляем две столовые ложки сахара.\n'
            'Разбиваем три яйца.',
      ],
    );
    expect(result.recipe.ingredients, [
      'Мука — 250 г',
      'Сахар — 2 ст. л.',
      'Яйцо — 3',
    ]);
  });
  test(
    'different units are rejected and verified egg count keeps no invented unit',
    () {
      final data = answer();
      data['ingredients'] = [
        {
          'name': 'Мука',
          'quantity': '200 мл',
          'evidence': [1],
        },
        {
          'name': 'Яйцо',
          'quantity': '3 шт.',
          'evidence': [2],
        },
      ];
      data['steps'] = [];
      final result = decode(
        [jsonEncode(data)],
        ['Берём двести граммов муки.\nРазбиваем три яйца.'],
      );
      expect(result.recipe.ingredients, [
        'Мука — количество не указано',
        'Яйцо — 3',
      ]);
    },
  );
  test('recorded Qwen3 response preserves actions and rejects added units', () {
    final transcript = File(
      'test/fixtures/local_ai_recipe_ru.txt',
    ).readAsStringSync();
    final outputs =
        (jsonDecode(
                  File(
                    'test/fixtures/local_ai_qwen17_output.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<String>();
    final result = decodeAiRecipes(
      outputs,
      splitTranscript(transcript),
      source: transcript,
      sourceUrl: 'https://youtu.be/abcdefghijk?t=18',
      fallbackTitle: 'Видео',
    );
    expect(result.recipe.title, 'Оладьи');
    expect(result.recipe.ingredients, [
      'Мука — 200 г',
      'Яйцо — 1',
      'Сахар — 2 ст. л.',
      'Молоко — количество не указано',
    ]);
    expect(result.recipe.steps, sourceLines(transcript).sublist(1, 4));
    expect(result.recipe.time, '15 минут');
    expect(result.recipe.servings, '2 порции');
    expect(result.recipe.sourceText, transcript);
    expect(result.recipe.sourceUrl, 'https://youtu.be/abcdefghijk?t=18');
  });
  test(
    'indexed evidence preserves source action rather than invented paraphrase',
    () {
      final data = answer();
      data['ingredients'] = [
        {
          'name': 'Мука',
          'quantity': '200 г',
          'evidence': [1],
        },
      ];
      data['steps'] = [
        {
          'text': 'Выпекайте час.',
          'evidence': [2],
        },
      ];
      data['time'] = {'value': '', 'evidence': []};
      data['servings'] = {'value': '', 'evidence': []};
      final result = decode([jsonEncode(data)], [source]);
      expect(result.recipe.steps, ['[0:20] Смешайте муку с молоком.']);
      expect(result.recipe.ingredients, ['Мука — 200 г']);
    },
  );
  test(
    'indexed cooking steps follow source order even when model reverses them',
    () {
      final text = '[0:10] Промойте рис.\n[0:20] Варите рис в воде.';
      final data = answer();
      data['ingredients'] = [];
      data['steps'] = [
        {
          'evidence': [2],
        },
        {
          'evidence': [1],
        },
      ];
      final result = decode([jsonEncode(data)], [text]);
      expect(result.recipe.steps, sourceLines(text));
    },
  );
  test('invalid source line numbers cannot create a recipe', () {
    final data = answer();
    data['ingredients'] = [
      {
        'name': 'Мука',
        'quantity': '200 г',
        'evidence': [99],
      },
    ];
    expect(() => decode([jsonEncode(data)], [source]), throwsFormatException);
  });
  test(
    'digits in timestamps or inside other quantities do not confirm an amount',
    () {
      final data = answer();
      data['ingredients'] = [
        {
          'name': 'Мука',
          'quantity': '20',
          'evidence': [1],
        },
      ];
      final result = decode([jsonEncode(data)], [source]);
      expect(result.recipe.ingredients.single, 'Мука — количество не указано');
    },
  );
  test(
    'numbered model input fits the native bound even for very short lines',
    () {
      final raw = List.filled(800, 'а').join('\n');
      expect(numberedTranscript(raw).length, lessThanOrEqualTo(2400));
      expect(sourceLines(raw).length, lessThanOrEqualTo(100));
    },
  );
  test(
    'verified quantities and unknown amounts remain distinguishable; URL and transcript preserved',
    () {
      final result = decode([jsonEncode(answer())], [source]);
      expect(result.recipe.ingredients, [
        'Мука — 200 г',
        'Молоко — количество не указано',
      ]);
      expect(result.recipe.sourceUrl, 'https://youtu.be/abcdefghijk?t=12');
      expect(result.recipe.sourceText, source);
      expect(result.recipe.steps.single, startsWith('[0:20]'));
      expect(result.recipe.draft, false);
    },
  );
  test('invented quantity is replaced by unknown', () {
    final data = answer();
    (data['ingredients'] as List)[1]['quantity'] = '500 мл';
    final result = decode([jsonEncode(data)], [source]);
    expect(result.recipe.ingredients.last, 'Молоко — количество не указано');
    expect(result.warnings.join(), contains('не подтверждено'));
  });
  test(
    'model cannot introduce unquoted ingredient, step, cooking time or source URL',
    () {
      final data = answer();
      (data['ingredients'] as List).add({
        'name': 'Яйцо',
        'quantity': '1 шт.',
        'evidence': 'Добавьте яйцо',
      });
      (data['steps'] as List).add({
        'text': 'Выпекайте при 200 градусах',
        'evidence': 'Выпекайте при 200 градусах',
      });
      data['time'] = {'value': '30 мин', 'evidence': '30 мин'};
      data['sourceUrl'] = 'https://wrong.example.com';
      final result = decode([jsonEncode(data)], [source]);
      expect(result.recipe.ingredients.length, 2);
      expect(result.recipe.steps.length, 1);
      expect(result.recipe.time, isEmpty);
      expect(result.recipe.draft, true);
      expect(result.recipe.sourceUrl, contains('youtu.be'));
    },
  );
  test('one failed fragment yields a draft without losing valid sections', () {
    final result = decode(
      [jsonEncode(answer()), '{unfinished'],
      [source, 'конец видео'],
    );
    expect(result.recipe.ingredients.length, 2);
    expect(result.recipe.draft, true);
    expect(result.warnings.join(), contains('фрагмент'));
  });
  test(
    'overlapping fragments do not duplicate identical ingredients or steps',
    () {
      final result = decode(
        [jsonEncode(answer()), jsonEncode(answer())],
        [source, source],
      );
      expect(result.recipe.ingredients.length, 2);
      expect(result.recipe.steps.length, 1);
    },
  );
  test('quantity mentioned later replaces the earlier unknown entry', () {
    final later = answer();
    later['ingredients'] = [
      {'name': 'Молоко', 'quantity': '300 мл', 'evidence': '300 мл молока'},
    ];
    later['steps'] = [];
    final result = decode(
      [jsonEncode(answer()), jsonEncode(later)],
      [source, 'Далее добавляем 300 мл молока.'],
    );
    expect(result.recipe.ingredients, ['Мука — 200 г', 'Молоко — 300 мл']);
    expect(
      result.warnings.join(),
      isNot(contains('количество не подтверждено')),
    );
  });
  test(
    'all invalid outputs are rejected; incomplete batch is not accepted',
    () {
      expect(() => decode(['broken'], [source]), throwsFormatException);
      expect(() => decode([], [source]), throwsFormatException);
    },
  );
  test(
    'fragmentation covers a long Russian transcript including its ending and emoji',
    () {
      final text = List.generate(
        1200,
        (i) => '[$i:00] Добавляем муку 🍞 и молоко.',
      ).join('\n');
      final fragments = splitTranscript(text);
      expect(fragments.length, greaterThan(1));
      expect(fragments.every((s) => s.length <= 1800), true);
      expect(fragments.last, endsWith('молоко.'));
      final joined = fragments.join('\n');
      for (var i = 0; i < 1200; i++) {
        expect(joined, contains('[$i:00] Добавляем муку 🍞 и молоко.'));
      }
    },
  );
  test(
    'old settings preserve identity and gain local AI default; disabled persists',
    () {
      final settings = AppSettings.fromJson({'deviceId': 'original'});
      expect(settings.deviceId, 'original');
      expect(settings.localAi, true);
      settings.localAi = false;
      expect(AppSettings.fromJson(settings.toJson()).localAi, false);
    },
  );
}
