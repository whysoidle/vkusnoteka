// Usage: dart run tool/check_local_ai.dart prepare SOURCE.txt REQUEST.json
//        dart run tool/check_local_ai.dart check REQUEST.json OUTPUT.json
import 'dart:convert';
import 'dart:io';
import 'package:recipe_vault/services/recipe_ai_parser.dart';
import 'package:recipe_vault/services/windows_ai_protocol.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3 || !['prepare', 'check'].contains(args.first)) {
    stderr.writeln(
      'Usage: prepare SOURCE.txt REQUEST.json | check REQUEST.json OUTPUT.json',
    );
    exitCode = 2;
    return;
  }
  if (args.first == 'prepare') {
    final source = await File(args[1]).readAsString();
    await File(args[2]).writeAsString(
      jsonEncode({
        'source': source,
        'instruction': recipeAiInstruction,
        'chatTemplate': recipeAiChatTemplate,
        'schema': recipeAiSchema,
        'rawFragments': splitTranscript(source),
        'fragments': splitTranscript(source).map(numberedTranscript).toList(),
        'windowsRequests': [
          for (final fragment in splitTranscript(source))
            windowsCompletionBody(
              windowsRecipeAiInstruction,
              numberedTranscript(fragment),
              jsonEncode(recipeAiSchema),
            ),
        ],
      }),
    );
    stdout.writeln(
      'Prepared inference request using the app prompt and schema.',
    );
  } else {
    final request = jsonDecode(await File(args[1]).readAsString()) as Map;
    final outputs = (jsonDecode(await File(args[2]).readAsString()) as List)
        .cast<String>();
    final result = decodeAiRecipes(
      outputs,
      (request['rawFragments'] as List).cast<String>(),
      source: request['source'] as String,
      sourceUrl: 'https://youtu.be/abcdefghijk',
      fallbackTitle: 'Проверка локального ИИ',
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'recipe': result.recipe.toJson(),
        'warnings': result.warnings,
      }),
    );
    if (result.recipe.ingredients.isEmpty || result.recipe.steps.isEmpty) {
      exitCode = 1;
    }
  }
}
