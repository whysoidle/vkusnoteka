import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/import_job.dart';
import 'package:recipe_vault/services/import_service.dart';
import 'package:recipe_vault/services/local_recipe_ai.dart';
import 'package:recipe_vault/services/youtube_subtitles.dart';
import 'fixtures/video_recipe_sample.dart' as fixture;

class FakeVideo implements VideoSourceProvider {
  final VideoSource source;
  const FakeVideo(this.source);
  @override
  Future<VideoSource> load(String url, ImportJob job) async => source;
}

class FakeAi implements RecipeAi {
  final bool installed, fail;
  bool called = false;
  List<Recipe> receivedOutlines = [];
  String receivedText = '';
  FakeAi({this.installed = true, this.fail = false});
  @override
  Future<bool> get ready async => installed;
  @override
  Future<LocalAiResult> extract(
    String text, {
    required String title,
    required String sourceUrl,
    required ImportJob job,
    List<Recipe> outlines = const [],
    void Function(String)? onProgress,
  }) async {
    called = true;
    receivedOutlines = outlines;
    receivedText = text;
    if (fail) throw StateError('inference failed');
    return LocalAiResult(
      Recipe(
        id: 'ai',
        title: title,
        sourceUrl: sourceUrl,
        sourceText: text,
        ingredients: ['Мука — 200 г'],
        steps: ['Смешайте.'],
        draft: false,
      ),
      ['Проверьте карточку.'],
      recipes: outlines.isEmpty
          ? null
          : [
              for (final outline in outlines)
                Recipe.fromJson({
                  ...outline.toJson(),
                  'steps': ['Смешайте.'],
                  'draft': false,
                }),
            ],
    );
  }
}

const url = 'https://youtu.be/abcdefghijk?t=20';
void main() {
  test(
    'video import returns distinct cards and sends captions without ads',
    () async {
      final ai = FakeAi();
      final result = await ImportService(
        ai: ai,
        videos: const FakeVideo(
          VideoSource(
            title: 'Два варианта теста',
            description: fixture.description,
            transcript: '[0:20] Смешайте яйца с молоком.',
          ),
        ),
      ).parse(url, server: '', localAi: true);
      expect(ai.receivedOutlines.length, 2);
      expect(ai.receivedText, '[0:20] Смешайте яйца с молоком.');
      expect(result.recipes.length, 2);
      expect(
        result.recipes.first.ingredients,
        fixture.outlines.first.ingredients,
      );
      expect(
        result.recipes.last.ingredients,
        fixture.outlines.last.ingredients,
      );
      expect(
        result.recipes.every((r) => r.sourceText.contains('Подписка')),
        true,
      );
      expect(result.recipes.every((r) => r.sourceUrl == url), true);
    },
  );
  test('failed model keeps two separate published ingredient lists', () async {
    final result = await ImportService(
      ai: FakeAi(fail: true),
      videos: const FakeVideo(
        VideoSource(
          title: 'Два варианта',
          description: fixture.description,
          transcript: '[0:20] Смешайте.',
        ),
      ),
    ).parse(url, server: '', localAi: true);
    expect(result.recipes.length, 2);
    expect(result.recipes.every((r) => r.draft), true);
    expect(result.recipes.last.ingredients, fixture.outlines.last.ingredients);
  });
  test(
    'available subtitles are interpreted locally even with remote service configured',
    () async {
      final ai = FakeAi();
      final result =
          await ImportService(
            ai: ai,
            videos: const FakeVideo(
              VideoSource(
                title: 'Тесто',
                transcript: '[0:20] Берём двести граммов муки и смешиваем.',
              ),
            ),
          ).parse(
            url,
            server: 'https://must-not-be-called.example.com',
            localAi: true,
          );
      expect(ai.called, true);
      expect(ai.receivedOutlines, isEmpty);
      expect(ai.receivedText, contains('двести граммов муки'));
      expect(result.recipes.single.sourceUrl, url);
      expect(result.recipes.single.draft, false);
    },
  );
  test(
    'two ingredient lists survive unavailable subtitles without merging',
    () async {
      final ai = FakeAi();
      final result = await ImportService(
        ai: ai,
        videos: const FakeVideo(
          VideoSource(title: 'Два варианта', description: fixture.description),
        ),
      ).parse(url, server: '', localAi: true);
      expect(ai.called, false);
      expect(result.recipes.length, 2);
      expect(result.recipes.every((r) => r.draft && r.steps.isEmpty), true);
      expect(
        result.recipes.last.ingredients,
        fixture.outlines.last.ingredients,
      );
      expect(result.warnings.join(), contains('Без доступных субтитров'));
    },
  );
  test(
    'without model captions and exact URL remain in an editable draft',
    () async {
      final ai = FakeAi(installed: false);
      final result = await ImportService(
        ai: ai,
        videos: const FakeVideo(
          VideoSource(title: 'Тесто', transcript: '[0:20] Берём муку.'),
        ),
      ).parse(url, server: '', localAi: true);
      expect(ai.called, false);
      expect(result.recipes.single.sourceText, contains('Берём муку'));
      expect(result.recipes.single.sourceUrl, url);
      expect(result.warnings.join(), contains('скачайте модель'));
    },
  );
  test(
    'inference failure retains raw subtitles, title and source for manual filling',
    () async {
      final result = await ImportService(
        ai: FakeAi(fail: true),
        videos: const FakeVideo(
          VideoSource(title: 'Тесто', transcript: 'Добавим муку и смешаем.'),
        ),
      ).parse(url, server: '', localAi: true);
      expect(result.recipes.single.draft, true);
      expect(result.recipes.single.sourceUrl, url);
      expect(result.recipes.single.sourceText, 'Добавим муку и смешаем.');
      expect(result.recipes.single.title, 'Тесто');
    },
  );
  test(
    'video without any recipe text does not call inference or lose URL',
    () async {
      final ai = FakeAi();
      final result = await ImportService(
        ai: ai,
        videos: const FakeVideo(VideoSource(title: 'Видео')),
      ).parse(url, server: '', localAi: true);
      expect(ai.called, false);
      expect(result.recipes.single.sourceUrl, url);
      expect(result.recipes.single.draft, true);
    },
  );
  test(
    'cancelled import throws cancellation instead of disguising it as network failure',
    () async {
      final job = ImportJob()..cancel();
      await expectLater(
        ImportService(
          ai: FakeAi(),
          videos: const FakeVideo(VideoSource(title: 'Видео')),
        ).parse(url, server: '', localAi: true, job: job),
        throwsA(isA<ImportCancelled>()),
      );
    },
  );
}
