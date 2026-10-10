import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/recipe_tools.dart';

void main() {
  test('YouTube share, shorts and watch links identify the same recipe', () {
    expect(
      canonicalRecipeUrl('https://youtu.be/abcdefghijk?t=30'),
      canonicalRecipeUrl('https://www.youtube.com/watch?v=abcdefghijk&si=abc'),
    );
    expect(
      canonicalRecipeUrl('https://youtube.com/shorts/abcdefghijk'),
      'youtube:abcdefghijk',
    );
  });
  test('site recipe identity retains meaningful query and strips tracking', () {
    expect(
      canonicalRecipeUrl(
        'http://www.russianfood.com/recipes/recipe.php?utm_source=x&rid=1',
      ),
      canonicalRecipeUrl('https://russianfood.com/recipes/recipe.php?rid=1'),
    );
    expect(
      canonicalRecipeUrl('https://russianfood.com/recipes/recipe.php?rid=1'),
      isNot(
        canonicalRecipeUrl('https://russianfood.com/recipes/recipe.php?rid=2'),
      ),
    );
  });
  test('duplicate recipe is offered by source or similar ingredients', () {
    const old = Recipe(
      id: 'old',
      title: 'Сырники',
      sourceUrl: 'https://youtu.be/abcdefghijk',
      ingredients: ['Творог — 400 г'],
    );
    expect(
      duplicateRecipes(
        const Recipe(
          id: 'new',
          title: 'Видео',
          sourceUrl: 'https://youtube.com/watch?v=abcdefghijk',
        ),
        [old],
      ).single.id,
      'old',
    );
    expect(duplicateRecipes(old, [old]), isEmpty);
    expect(
      duplicateRecipes(const Recipe(id: 'new', title: 'Сырники'), [old]).length,
      1,
    );
  });
  test(
    'updating import preserves user metadata and does not erase missing sections',
    () {
      const old = Recipe(
        id: 'old',
        title: 'Суп',
        favorite: true,
        photo: 'photo',
        tags: ['Домашнее'],
        collections: ['Хочу приготовить'],
        notes: 'Люблю погуще',
        ingredients: ['Морковь — 100 г'],
        steps: ['Варить'],
      );
      final merged = mergeImportedRecipe(
        old,
        const Recipe(id: 'new', title: 'Суп', notes: 'Проверьте количество'),
      );
      expect(merged.id, old.id);
      expect(merged.ingredients, old.ingredients);
      expect(merged.photo, old.photo);
      expect(merged.tags, old.tags);
      expect(merged.favorite, true);
      expect(merged.notes, contains(old.notes));
    },
  );
  test(
    'portion scaling handles decimals, fractions, mixed numbers and ranges',
    () {
      expect(scaleIngredient('Мука — 200 г', 1.5), 'Мука — 300 г');
      expect(scaleIngredient('Молоко — 0,5 л', 2), 'Молоко — 1 л');
      expect(scaleIngredient('Мука — 1 1/2 стакана', 2), 'Мука — 3 стакана');
      expect(scaleIngredient('Сахар — ½ ст. л.', 2), 'Сахар — 1 ст. л.');
      expect(scaleIngredient('Яйцо — 1–2 шт.', 2), 'Яйцо — 2–4 шт.');
    },
  );
  test('product percentages and ambiguous quantities are unchanged', () {
    expect(scaleIngredient('Сливки 20% — 100 мл', 2), 'Сливки 20% — 200 мл');
    expect(scaleIngredient('Соль — по вкусу', 2), 'Соль — по вкусу');
    expect(
      scaleIngredient('Молоко — количество не указано', 2),
      'Молоко — количество не указано',
    );
    expect(scaleIngredient('Сыр 45%', 2), 'Сыр 45%');
  });
  test('portion scaling accepts comma-separated ingredient quantities', () {
    const cases = {
      'Куриный бульон, 800 мл': 'Куриный бульон, 1600 мл',
      'Кокосовые сливки, 400 мл': 'Кокосовые сливки, 800 мл',
      'Куркума, 8 г': 'Куркума, 16 г',
      'Смесь тандури-масала,  по вкусу': 'Смесь тандури-масала,  по вкусу',
      'Желтая паста карри , 20 г': 'Желтая паста карри , 40 г',
      'Чеснок, 1 головка': 'Чеснок, 2 головка',
      'Хумус, 160 г': 'Хумус, 320 г',
    };
    for (final entry in cases.entries) {
      expect(scaleIngredient(entry.key, 2), entry.value);
    }
    expect(scaleIngredient('Куркума, 8 г', .5), 'Куркума, 4 г');
    expect(scaleIngredient('Хумус,160 г', 2), 'Хумус,320 г');
    expect(scaleIngredient('Молоко, 0,5 л', 2), 'Молоко, 1 л');
    expect(scaleIngredient('Мука, 1 1/2 стакана', 2), 'Мука, 3 стакана');
    expect(scaleIngredient('Сахар, ½ ст. л.', 2), 'Сахар, 1 ст. л.');
    expect(scaleIngredient('Яйцо, 1–2 шт.', 2), 'Яйцо, 2–4 шт.');
  });
  test(
    'quantity commas are distinct from decimals and product descriptions',
    () {
      expect(
        scaleIngredient('Сливки 20,5%, 100 мл', 2),
        'Сливки 20,5%, 200 мл',
      );
      expect(scaleIngredient('Сливки, 20%, 100 мл', 2), 'Сливки, 20%, 200 мл');
      expect(
        scaleIngredient('Томаты, нарезанные, 400 г', 2),
        'Томаты, нарезанные, 800 г',
      );
      expect(scaleIngredient('Мука сорта 1, 200 г', 2), 'Мука сорта 1, 400 г');
      expect(
        scaleIngredient('Бульон, 800 мл — домашний', 2),
        'Бульон, 1600 мл — домашний',
      );
      for (final value in ['Сливки 20,5%', 'Молоко, количество не указано']) {
        expect(scaleIngredient(value, 2), value);
      }
      expect(scaleIngredient('Мука 1,5 кг', 2), 'Мука 3 кг');
    },
  );
  test(
    'portion and time parsing are explicit and do not assume a missing unit',
    () {
      expect(parseServings('2 порции'), 2);
      expect(parseServings('2'), 2);
      expect(parseServings('0'), isNull);
      expect(recipeMinutes('1 час 20 минут'), 80);
      expect(recipeMinutes('1,5 часа'), 90);
      expect(recipeMinutes('быстро'), isNull);
    },
  );
  test('timer reads intervals and ignores YouTube timestamp', () {
    expect(stepDurations('[1:20] Варить 15–20 минут, обжарить 30 секунд.'), [
      const Duration(minutes: 20),
      const Duration(seconds: 30),
    ]);
  });
  test(
    'old database gains empty metadata, new photo and tags survive merging',
    () {
      final recipe = Recipe.fromJson({'id': 'old', 'title': 'Суп'});
      expect(recipe.tags, isEmpty);
      expect(recipe.photo, '');
      const enriched = Recipe(
        id: 'new',
        title: 'Суп',
        tags: ['Быстро'],
        collections: ['На каждый день'],
        photo: 'thumbnail',
      );
      final db = RecipeDatabase()..put(enriched, 'a');
      final decoded = RecipeDatabase.decode(db.encode()).recipes.single;
      expect(decoded.photo, enriched.photo);
      expect(decoded.tags, enriched.tags);
      expect(decoded.collections, enriched.collections);
    },
  );
}
