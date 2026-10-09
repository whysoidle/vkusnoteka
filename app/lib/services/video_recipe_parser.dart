import 'dart:convert';
import '../models/recipe.dart';
import 'recipe_ai_parser.dart';
import 'text_parser.dart';

/// Published ingredient lists are authoritative. In particular, two recipes in
/// one video must not become one list with conflicting quantities.
List<Recipe> videoRecipeOutlines(
  String description, {
  required String title,
  required String sourceUrl,
}) {
  final lines = description.split('\n').map((s) => s.trim()).toList();
  final heading = RegExp(r'^рецепт(?:\s|[:№])', caseSensitive: false);
  final quantity = RegExp(
    r'(?:\d|по вкусу|щепотк|половин|полстакана|поллитра)',
    caseSensitive: false,
  );
  final action = RegExp(
    r'^(?:смеш|добав|разогр|обжар|жар|выпек|выпека|вар|перемеш|нагре|готов|просе)',
    caseSensitive: false,
  );
  bool ingredient(String line) =>
      line.length <= 160 &&
      !line.contains(RegExp(r'https?://|#')) &&
      !action.hasMatch(line) &&
      quantity.hasMatch(line);
  final outlines = <Recipe>[];
  for (var i = 0; i < lines.length; i++) {
    if (!heading.hasMatch(lines[i])) continue;
    final ingredients = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].isEmpty && ingredients.isEmpty) continue;
      if (!ingredient(lines[j])) break;
      ingredients.add(lines[j].replaceFirst(RegExp(r'^[-•*]\s*'), ''));
    }
    if (ingredients.length < 2) continue;
    outlines.add(
      Recipe(
        id: Recipe.blank().id,
        title: lines[i].replaceFirst(RegExp(r'[:：]\s*$'), ''),
        ingredients: ingredients,
        sourceUrl: sourceUrl,
        sourceText: description,
      ),
    );
  }
  // Avoid an unbounded prompt on compilations with dozens of recipes.
  if (outlines.isNotEmpty) return outlines;
  final parsed = parseText(description, title: title, sourceUrl: sourceUrl);
  return parsed.ingredients.length >= 2 ? [parsed] : [];
}

String videoStepsInstruction(List<Recipe> outlines) =>
    '''Извлеки действия приготовления из автоматических субтитров кулинарного видео.
В субтитрах нет пунктуации и есть ошибки распознавания речи. Это нормально: не обсуждай ошибки текста, а найди действия повара.
Рецепты с уже известными продуктами:
${jsonEncode([
      for (var i = 0; i < outlines.length; i++) {'index': i + 1, 'title': outlines[i].title, 'ingredients': outlines[i].ingredients},
    ])}
Верни JSON: {"recipes":[{"index":1,"steps":[{"evidence":[2,3]},{"evidence":[4]}]}]}.
index — номер рецепта из списка выше. evidence — номера строк источника в квадратных скобках, начиная с 1. Это ссылки на текст, не ингредиенты и не таймеры.
Выбери ВСЕ строки, где повар нагревает, смешивает, добавляет продукты, даёт тесту постоять или жарит. Объедини соседние строки одного действия в один шаг. Числа и названия продуктов помогут отличить первый рецепт от второго. Для общих действий над обоими рецептами можно указать одинаковые строки в обоих рецептах.
В сообщении дан фрагмент готовки. Найди действия приготовления; не включай приветствия, рекламу, просьбы подписаться и разговоры о канале. Не придумывай строк.
Пример источника: [1] Всем привет. [2] Я нагреваю молоко [3] до сорока градусов [4] а потом смешиваю яйца с сахаром.
Пример ответа для рецепта 1: {"recipes":[{"index":1,"steps":[{"evidence":[2,3]},{"evidence":[4]}]}]}.
Теперь обработай только источник из сообщения пользователя.''';

Map<String, dynamic> videoStepsSchema(int count, {List<int>? indexes}) => {
  'type': 'object',
  'properties': {
    'recipes': {
      'type': 'array',
      'minItems': 1,
      'maxItems': count,
      'items': {
        'type': 'object',
        'properties': {
          'index': {
            'type': 'integer',
            'enum': indexes ?? List.generate(count, (i) => i + 1),
          },
          'steps': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 30,
            'items': {
              'type': 'object',
              'properties': {
                'evidence': {
                  'type': 'array',
                  'minItems': 1,
                  'maxItems': 8,
                  'items': {'type': 'integer', 'minimum': 1},
                },
              },
              'required': ['evidence'],
              'additionalProperties': false,
            },
          },
        },
        'required': ['index', 'steps'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['recipes'],
  'additionalProperties': false,
};

List<String> videoCookingFragments(String text) {
  final cooking = RegExp(
    r'(?<![а-я])(?:беру|бер[её]м|разбива[а-я]*|разогре[а-я]*|нагрева[а-я]*|просеи[а-я]*|всып[а-я]*|налива[а-я]*|влива[а-я]*|добавля[а-я]*|добавить|смеш[а-я]*|перемеш[а-я]*|взбива[а-я]*|жар[а-я]*|обжари[а-я]*|выпека[а-я]*|запека[а-я]*|варим|варите|варить|кипяти[а-я]*|смазыва[а-я]*|нареза[а-я]*|режем|почист[а-я]*|очист[а-я]*|замеш[а-я]*|раскат[а-я]*|выкладыва[а-я]*|переворачива[а-я]*|настояться|постоять|доводим до кипения)',
    caseSensitive: false,
  );
  return splitTranscript(text).where(cooking.hasMatch).toList();
}

/// Shared amounts cannot select a recipe; only distinct measurements or an
/// explicit recipe ordinal constrain the model's attribution.
List<int> videoFragmentRecipeIndexes(String fragment, List<Recipe> outlines) {
  final measurements = outlines
      .map((r) => recipeMeasurements(r.ingredients.join('\n')))
      .toList();
  final stated = recipeMeasurements(
    fragment.replaceAll(RegExp(r'\[\d+:\d+\]'), ''),
  );
  final scores = [
    for (var i = 0; i < measurements.length; i++)
      measurements[i]
          .where(
            (value) =>
                stated.contains(value) &&
                ![
                  for (var j = 0; j < measurements.length; j++)
                    if (j != i) measurements[j],
                ].any((other) => other.contains(value)),
          )
          .length,
  ];
  if (scores.any((score) => score > 0)) {
    return [
      for (var i = 0; i < scores.length; i++)
        if (scores[i] > 0) i + 1,
    ];
  }
  final plain = fragment.replaceAll(RegExp(r'\[\d+:\d+\]'), ' ');
  final ordinals = [
    'перв(?:ый|ого|ому)',
    'втор(?:ой|ого|ому)',
    'трет(?:ий|ьего|ьему)',
  ];
  final mentioned = [
    for (var i = 0; i < outlines.length && i < ordinals.length; i++)
      if (RegExp(
        '${ordinals[i]}\\s+(?:[а-я]+\\s+){0,3}рецепт',
        caseSensitive: false,
      ).hasMatch(plain))
        i + 1,
  ];
  return mentioned.length == 1
      ? mentioned
      : List.generate(outlines.length, (i) => i + 1);
}

LocalAiResult decodeVideoSteps(
  List<String> outputs,
  List<String> fragments,
  List<Recipe> outlines, {
  required String source,
  required String sourceUrl,
}) {
  if (outlines.isEmpty || outputs.length != fragments.length) {
    throw const FormatException('Неполный ответ модели');
  }
  final batches = List.generate(outlines.length, (_) => <String>[]);
  var valid = 0;
  for (final output in outputs) {
    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map || decoded['recipes'] is! List) {
        throw const FormatException('Неверный ответ модели');
      }
      final entries = <int, Map>{};
      for (final raw in decoded['recipes'] as List) {
        if (raw is! Map ||
            raw['index'] is! int ||
            (raw['index'] as int) < 1 ||
            (raw['index'] as int) > outlines.length ||
            raw['steps'] is! List) {
          throw const FormatException('Неверный номер рецепта');
        }
        final index = raw['index'] as int;
        final previous = entries[index];
        entries[index] = {
          ...?previous,
          ...raw,
          'steps': [...?previous?['steps'] as List?, ...raw['steps'] as List],
        };
      }
      for (var i = 0; i < outlines.length; i++) {
        batches[i].add(
          jsonEncode({
            'title': '',
            'ingredients': [],
            'steps': [],
            'time': {'value': '', 'evidence': []},
            'servings': {'value': '', 'evidence': []},
            'warnings': [],
            ...?entries[i + 1],
          }),
        );
      }
      valid++;
    } catch (_) {
      for (final batch in batches) {
        batch.add('{invalid');
      }
    }
  }
  if (valid == 0) throw const FormatException('Модель не вернула рецепт');
  final results = [
    for (var i = 0; i < outlines.length; i++)
      decodeAiRecipes(
        batches[i],
        fragments,
        source: source,
        sourceUrl: sourceUrl,
        fallbackTitle: outlines[i].title,
        confirmedIngredients: outlines[i].ingredients,
      ),
  ];
  return LocalAiResult(
    results.first.recipe,
    results.expand((r) => r.warnings).toSet().toList(),
    recipes: results.map((r) => r.recipe).toList(),
  );
}
