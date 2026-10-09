// dart run tool/check_windows_ai.dart prepare REQUEST.json
// dart run tool/check_windows_ai.dart check REQUEST.json OUTPUT.json
import 'dart:convert';
import 'dart:io';
import 'package:recipe_vault/services/recipe_ai_parser.dart';
import 'package:recipe_vault/services/video_recipe_parser.dart';
import 'package:recipe_vault/services/windows_ai_protocol.dart';
import '../test/fixtures/video_recipe_sample.dart' as video;

const videoSource = '''[0:00] Сначала готовлю первый рецепт — тесто на молоке.
[0:10] Смешиваю два яйца с четырьмястами миллилитрами молока.
[0:25] Добавляю сто восемьдесят граммов муки и две столовые ложки масла. Перемешиваю тесто.
[0:40] Разогреваю сковороду и обжариваю блинчики с двух сторон.
[2:00] Теперь второй рецепт — тесто на воде.
[2:10] Смешиваю три яйца с тремястами миллилитрами воды.
[2:25] Добавляю двести пятьдесят граммов муки и соль по вкусу. Взбиваю тесто.
[2:40] Выливаю тесто на сковороду и жарю до румяной корочки.
[4:00] Подписка стоит 100 рублей. Подписывайтесь на канал!''';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    throw ArgumentError('prepare REQUEST | check REQUEST OUTPUT');
  }
  final requestFile = File(args[1]);
  if (args.first == 'prepare') {
    final text = await File(
      'test/fixtures/local_ai_recipe_ru.txt',
    ).readAsString();
    final textFragments = splitTranscript(text);
    final videoFragments = videoCookingFragments(videoSource);
    await requestFile.writeAsString(
      jsonEncode({
        'text': text,
        'textFragments': textFragments,
        'video': videoSource,
        'videoFragments': videoFragments,
        'cases': [
          [
            for (final f in textFragments)
              windowsCompletionBody(
                windowsRecipeAiInstruction,
                numberedTranscript(f),
                jsonEncode(recipeAiSchema),
              ),
          ],
          [
            for (final f in videoFragments)
              windowsCompletionBody(
                videoStepsInstruction(video.outlines),
                numberedTranscript(f),
                jsonEncode(
                  videoStepsSchema(
                    video.outlines.length,
                    indexes: videoFragmentRecipeIndexes(f, video.outlines),
                  ),
                ),
              ),
          ],
        ],
      }),
    );
    return;
  }
  final request = jsonDecode(await requestFile.readAsString()) as Map;
  final results = jsonDecode(await File(args[2]).readAsString()) as List;
  final text = decodeAiRecipes(
    (results[0] as List).cast<String>(),
    (request['textFragments'] as List).cast<String>(),
    source: request['text'] as String,
    sourceUrl: 'https://youtu.be/abcdefghijk',
    fallbackTitle: 'Оладьи',
  );
  final multiple = decodeVideoSteps(
    (results[1] as List).cast<String>(),
    (request['videoFragments'] as List).cast<String>(),
    video.outlines,
    source: request['video'] as String,
    sourceUrl: 'https://youtu.be/abcdefghijk',
  );
  void require(bool valid, String reason) {
    if (!valid) throw StateError(reason);
  }

  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'single': text.recipe.toJson(),
      'singleWarnings': text.warnings,
      'multiple': multiple.recipes.map((r) => r.toJson()).toList(),
      'multipleWarnings': multiple.warnings,
    }),
  );

  require(
    text.recipe.ingredients.length == 4,
    'Expected all four edible ingredients',
  );
  require(
    text.recipe.ingredients.contains('Мука — 200 г'),
    'Exact flour quantity',
  );
  require(text.recipe.ingredients.contains('Яйцо — 1'), 'No invented egg unit');
  require(
    text.recipe.ingredients.contains('Сахар — 2 ст. л.'),
    'Exact sugar quantity',
  );
  require(
    text.recipe.ingredients.contains('Молоко — количество не указано'),
    'Unknown milk quantity',
  );
  require(
    text.recipe.time == '15 минут' && text.recipe.servings == '2 порции',
    'Time and servings evidence',
  );
  require(
    text.recipe.steps.join().contains('обжариваю'),
    'Last cooking action preserved',
  );
  require(multiple.recipes.length == 2, 'Both recipes survive');
  for (var i = 0; i < 2; i++) {
    require(
      jsonEncode(multiple.recipes[i].ingredients) ==
          jsonEncode(video.outlines[i].ingredients),
      'Published ingredients must stay verbatim',
    );
    require(
      multiple.recipes[i].steps.isNotEmpty,
      'Cooking actions for recipe ${i + 1}',
    );
    require(
      !multiple.recipes[i].steps.join().contains('100 рублей'),
      'Ads excluded',
    );
  }
  require(
    !multiple.recipes.first.steps.join().contains('тремястами'),
    'Second recipe cannot leak into first',
  );
  require(
    !multiple.recipes.last.steps.join().contains('четырьмястами'),
    'First recipe cannot leak into second',
  );
  stdout.writeln(
    'Actual Qwen3 4B: quantities, unknown amounts, source evidence, separate recipes and ad exclusion passed.',
  );
}
