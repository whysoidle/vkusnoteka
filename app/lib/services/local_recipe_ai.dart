import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'recipe_ai_parser.dart';
export 'recipe_ai_parser.dart';
import 'import_job.dart';
import 'local_model_store.dart';
import '../models/recipe.dart';
import 'video_recipe_parser.dart';

abstract class RecipeAi {
  Future<bool> get ready;
  Future<LocalAiResult> extract(
    String text, {
    required String title,
    required String sourceUrl,
    required ImportJob job,
    List<Recipe> outlines = const [],
    void Function(String)? onProgress,
  });
}

class LocalRecipeAi implements RecipeAi {
  static const channel = MethodChannel('recipe_vault/local_ai');
  static bool get supported => Platform.isAndroid || Platform.isMacOS;
  static Future<bool> get deviceSupported async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>('supported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static int _nextId = 0;
  static int? _activeId;
  @override
  Future<bool> get ready async =>
      await deviceSupported && await (await LocalModelStore.open()).ready;
  @override
  Future<LocalAiResult> extract(
    String text, {
    required String title,
    required String sourceUrl,
    required ImportJob job,
    List<Recipe> outlines = const [],
    void Function(String)? onProgress,
  }) async {
    job.check();
    if (!supported || text.length > 60000 || text.trim().isEmpty) {
      throw const FormatException('Текст не подходит для локального разбора');
    }
    final model = await LocalModelStore.open();
    if (!await model.ready) {
      throw const FormatException('Скачайте модель в настройках');
    }
    final id = ++_nextId;
    final fragments = outlines.isEmpty
        ? splitTranscript(text)
        : videoCookingFragments(text);
    if (fragments.isEmpty) {
      return LocalAiResult(outlines.first, [
        'В субтитрах не найдены действия приготовления. Добавьте шаги вручную.',
      ], recipes: outlines);
    }
    if (fragments.length > 64) {
      throw const FormatException('Слишком длинные субтитры');
    }
    job.check();
    if (_activeId != null) {
      throw const FormatException(
        'Локальная модель уже занята. Дождитесь текущего разбора.',
      );
    }
    _activeId = id;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && !job.cancelled) {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        if (data['id'] == id) onProgress?.call(data['text'] as String);
      }
    });
    final unregister = job.onCancel(() {
      channel
          .invokeMethod<void>('cancel', {'id': id})
          .catchError((Object _) {});
    });
    try {
      onProgress?.call('Загружаю локальную модель…');
      final result = await channel.invokeMapMethod<String, dynamic>('extract', {
        'id': id,
        'modelPath': model.file.path,
        'instruction': outlines.isEmpty
            ? recipeAiInstruction
            : videoStepsInstruction(outlines),
        'chatTemplate': recipeAiChatTemplate,
        'schema': jsonEncode(
          outlines.isEmpty ? recipeAiSchema : videoStepsSchema(outlines.length),
        ),
        'fragments': fragments.map(numberedTranscript).toList(),
        if (outlines.isNotEmpty)
          'fragmentSchemas': [
            for (final fragment in fragments)
              jsonEncode(
                videoStepsSchema(
                  outlines.length,
                  indexes: videoFragmentRecipeIndexes(fragment, outlines),
                ),
              ),
          ],
      });
      job.check();
      if (result == null) {
        throw const FormatException('Нет ответа локального ИИ');
      }
      final outputs = (result['outputs'] as List).cast<String>();
      final parsed = outlines.isEmpty
          ? decodeAiRecipes(
              outputs,
              fragments,
              source: text,
              sourceUrl: sourceUrl,
              fallbackTitle: title,
            )
          : decodeVideoSteps(
              outputs,
              fragments,
              outlines,
              source: text,
              sourceUrl: sourceUrl,
            );
      return LocalAiResult(parsed.recipe, [
        ...parsed.warnings,
        if (result['backend'] == 'CPU')
          'Модель использовала процессор устройства.',
      ], recipes: parsed.recipes);
    } catch (_) {
      job.check();
      rethrow;
    } finally {
      unregister();
      if (_activeId == id) {
        _activeId = null;
        channel.setMethodCallHandler(null);
      }
    }
  }
}
