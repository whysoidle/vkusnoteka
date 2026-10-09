import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import 'text_parser.dart';
import 'website_parser.dart';
import 'html_decoder.dart';
import 'import_job.dart';
import 'local_recipe_ai.dart';
import 'youtube_subtitles.dart';
import 'video_recipe_parser.dart';

class ImportResult {
  final List<Recipe> recipes;
  final List<String> warnings;
  const ImportResult(this.recipes, this.warnings);
}

class ImportService {
  final http.Client client;
  final RecipeAi ai;
  final VideoSourceProvider videos;
  ImportService({
    http.Client? client,
    RecipeAi? ai,
    VideoSourceProvider? videos,
  }) : client = client ?? http.Client(),
       ai = ai ?? LocalRecipeAi(),
       videos = videos ?? YouTubeSubtitles();

  Future<http.Response> _request(
    String method,
    Uri url,
    ImportJob job, {
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    final unregister = job.onCancel(stop);
    try {
      job.check();
      final request = http.AbortableRequest(
        method,
        url,
        abortTrigger: abort.future,
      );
      if (headers != null) request.headers.addAll(headers);
      if (body != null) request.body = body;
      final response = await client.send(request).timeout(timeout);
      if (method == 'GET' && response.statusCode != 200) {
        unawaited(
          response.stream.listen(null).cancel().catchError((Object _) {}),
        );
        return http.Response('', response.statusCode);
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        job.check();
        if (bytes.length + chunk.length > 3_000_000) {
          throw const FormatException(
            'Ответ слишком большой. Импортируйте рецепт меньшими частями.',
          );
        }
        bytes.addAll(chunk);
      }
      job.check();
      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      );
    } catch (_) {
      job.check();
      rethrow;
    } finally {
      unregister();
      // Also abort a pending send when its Future timed out.
      stop();
    }
  }

  Future<ImportResult> parse(
    String content, {
    required String server,
    String token = '',
    bool localAi = false,
    ImportJob? job,
    void Function(String)? onProgress,
  }) async {
    final work = job ?? ImportJob();
    work.check();
    final isUrl = RegExp(
      r'^https?://\S+$',
      caseSensitive: false,
    ).hasMatch(content.trim());
    if (localAi && isUrl && isYouTube(content.trim())) {
      return _localVideo(content.trim(), work, onProgress);
    }
    if (server.trim().isEmpty || (localAi && !isUrl)) {
      if (isUrl) {
        try {
          final response = await _request(
            'GET',
            Uri.parse(content.trim()),
            work,
          );
          if (response.statusCode != 200) {
            throw Exception('Источник недоступен');
          }
          final recipes = parseWebsite(
            decodeHtml(
              response.bodyBytes,
              contentType: response.headers['content-type'] ?? '',
            ),
            content.trim(),
          );
          work.check();
          return ImportResult(recipes, [
            if (isYouTube(content.trim()))
              'Использовано описание видео. Для субтитров можно подключить сервис импорта.',
            if (recipes.any((r) => r.draft))
              'Полный рецепт не найден. Ссылка сохранена: заполните карточку вручную или оставьте черновик.',
            'Проверьте карточку перед сохранением.',
          ]);
        } catch (_) {
          work.check();
          return ImportResult(
            [Recipe.blank(url: content.trim(), title: 'Рецепт по ссылке')],
            [
              'Источник недоступен. Ссылка сохранена: заполните карточку вручную или оставьте черновик.',
            ],
          );
        }
      }
      final recipe = parseText(content);
      if (localAi && recipe.draft && await ai.ready) {
        try {
          final result = await ai.extract(
            content,
            title: recipe.title,
            sourceUrl: '',
            job: work,
            onProgress: onProgress,
          );
          return ImportResult([result.recipe], result.warnings);
        } catch (_) {
          work.check();
          return ImportResult(
            [recipe],
            [
              'Локальный ИИ не завершил разбор. Исходный текст сохранён в карточке.',
            ],
          );
        }
      }
      return ImportResult(
        [recipe],
        ['Текст разобран на устройстве. Проверьте карточку перед сохранением.'],
      );
    }
    final response = await _request(
      'POST',
      Uri.parse('${server.replaceAll(RegExp(r'/+$'), '')}/import'),
      work,
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'content': content}),
      timeout: const Duration(seconds: 190),
    );
    work.check();
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw Exception(
        body['detail'] is String
            ? body['detail']
            : 'Сервис не смог обработать рецепт.',
      );
    }
    final recipes = (body['recipes'] as List)
        .map((j) => Recipe.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
    if (isUrl) {
      // Keep the exact input source even if upstream extraction omits it.
      for (var i = 0; i < recipes.length; i++) {
        recipes[i] = Recipe.fromJson({
          ...recipes[i].toJson(),
          'sourceUrl': content.trim(),
        });
      }
    }
    return ImportResult(
      recipes,
      (body['warnings'] as List? ?? []).cast<String>(),
    );
  }

  Future<ImportResult> _localVideo(
    String url,
    ImportJob job,
    void Function(String)? onProgress,
  ) async {
    onProgress?.call('Получаю описание и субтитры YouTube…');
    final video = await videos.load(url, job);
    job.check();
    final description = parseText(
      video.description,
      sourceUrl: url,
      title: video.title,
    );
    final outlines = videoRecipeOutlines(
      video.description,
      title: video.title,
      sourceUrl: url,
    );
    if (!description.draft && outlines.length <= 1) {
      return ImportResult(
        [description],
        ['Рецепт извлечён из описания видео. Проверьте карточку.'],
      );
    }
    final source = video.transcript.isNotEmpty
        ? '${video.description.trim().isEmpty ? '' : '${video.description}\n\n'}${video.transcript}'
        : video.description;
    final fallbacks = [
      for (final recipe in outlines.isEmpty ? [description] : outlines)
        Recipe.fromJson({...recipe.toJson(), 'sourceText': source}),
    ];
    if (outlines.length > 8 ||
        (outlines.isNotEmpty && video.transcript.trim().isEmpty)) {
      return ImportResult(fallbacks, [
        ...video.warnings,
        outlines.length > 8
            ? 'В видео больше восьми рецептов. Списки продуктов сохранены раздельно; добавьте шаги вручную.'
            : 'Ингредиенты сохранены из описания. Без доступных субтитров шаги приготовления нужно заполнить вручную.',
      ]);
    }
    if (!await ai.ready) {
      return ImportResult(fallbacks, [
        ...video.warnings,
        'Для разбора субтитров скачайте модель в настройках → «Локальный ИИ». Затем отправьте ссылку повторно.',
      ]);
    }
    final modelSource = outlines.isEmpty ? source : video.transcript;
    if (modelSource.trim().isEmpty || modelSource.length > 60000) {
      return ImportResult(fallbacks, [
        ...video.warnings,
        modelSource.length > 60000
            ? 'Текст слишком длинный. Вставьте в чат фрагмент с рецептом.'
            : 'Текста рецепта нет. Ссылка сохранена для ручного заполнения.',
      ]);
    }
    try {
      final result = await ai.extract(
        modelSource,
        title: video.title,
        sourceUrl: url,
        job: job,
        outlines: outlines,
        onProgress: onProgress,
      );
      job.check();
      return ImportResult(
        [
          for (final recipe in result.recipes)
            Recipe.fromJson({...recipe.toJson(), 'sourceText': source}),
        ],
        [...video.warnings, ...result.warnings],
      );
    } catch (_) {
      job.check();
      return ImportResult(fallbacks, [
        ...video.warnings,
        'Локальная модель не смогла разобрать рецепт. Исходный текст и ссылка сохранены; можно заполнить карточку вручную.',
      ]);
    }
  }
}
