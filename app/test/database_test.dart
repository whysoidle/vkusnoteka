import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/text_parser.dart';

Record record(
  String title,
  Map<String, int> clock, {
  String id = 'recipe',
  bool deleted = false,
}) => Record(
  id: id,
  modifiedAt: '2026-10-08T12:00:00.000Z',
  clock: clock,
  recipe: deleted ? null : Recipe(id: id, title: title),
);

void main() {
  test('round trip preserves source, drafts and tombstones', () {
    final db = RecipeDatabase()
      ..put(Recipe.blank(url: 'https://youtu.be/abcdefghijk'), 'android');
    db.put(const Recipe(id: 'other', title: 'Суп'), 'windows');
    db.remove('other', 'windows');
    final restored = RecipeDatabase.decode(db.encode());
    expect(restored.recipes.single.sourceUrl, 'https://youtu.be/abcdefghijk');
    expect(restored.records['other']!.deleted, true);
  });
  test('later edit supersedes prior edit', () {
    final a = RecipeDatabase({
      'recipe': record('Старая', {'android': 1}),
    });
    final b = RecipeDatabase({
      'recipe': record('Новая', {'android': 2}),
    });
    expect(mergeDatabases(a, b).recipes.single.title, 'Новая');
  });
  test(
    'concurrent edits are commutative, idempotent and preserve both versions',
    () {
      final a = RecipeDatabase({
        'recipe': record('Суп A', {'android': 1}),
      });
      final b = RecipeDatabase({
        'recipe': record('Суп B', {'windows': 1}),
      });
      final ab = mergeDatabases(a, b), ba = mergeDatabases(b, a);
      expect(ab.encode(), ba.encode());
      expect(ab.recipes.length, 2);
      expect(mergeDatabases(ab, ab).encode(), ab.encode());
      expect(mergeDatabases(ab, a).encode(), ab.encode());
      expect(mergeDatabases(ab, b).encode(), ab.encode());
    },
  );
  test('sequential delete remains deleted when an offline replica returns', () {
    final a = RecipeDatabase({
      'recipe': record('Суп', {'android': 1}),
    });
    final b = RecipeDatabase({
      'recipe': record('', {'android': 1, 'windows': 1}, deleted: true),
    });
    expect(mergeDatabases(a, b).recipes, isEmpty);
    expect(mergeDatabases(b, a).recipes, isEmpty);
  });
  test('concurrent deletion does not erase an offline edit', () {
    final a = RecipeDatabase({
      'recipe': record('Правка', {'android': 2}),
    });
    final b = RecipeDatabase({
      'recipe': record('', {'android': 1, 'windows': 1}, deleted: true),
    });
    expect(mergeDatabases(a, b).recipes.single.title, 'Правка');
    expect(mergeDatabases(a, b).encode(), mergeDatabases(b, a).encode());
  });
  test('resolved conflict is not resurrected from old replicas', () {
    final a = RecipeDatabase({
      'recipe': record('A', {'android': 1}),
    });
    final b = RecipeDatabase({
      'recipe': record('B', {'windows': 1}),
    });
    final combined = mergeDatabases(a, b);
    final conflict = combined.recipes.firstWhere(
      (r) => r.id.contains(':conflict:'),
    );
    combined.remove(conflict.id, 'android');
    expect(mergeDatabases(combined, a).recipes.length, 1);
    expect(mergeDatabases(combined, b).recipes.length, 1);
  });
  test('unknown schemas fail instead of overwriting data', () {
    expect(
      () => RecipeDatabase.decode('{"schemaVersion":2,"records":[]}'),
      throwsFormatException,
    );
  });
  test('offline text preserves quantities and does not invent ingredients', () {
    final recipe = parseText(
      'Сырники\nИнгредиенты:\nТворог — 400 г\nСоль по вкусу\nПриготовление:\n1. Смешайте.\n2. Обжарьте.\nВремя: 20 минут',
    );
    expect(recipe.ingredients, ['Творог — 400 г', 'Соль по вкусу']);
    expect(recipe.steps, ['Смешайте.', 'Обжарьте.']);
    expect(recipe.draft, false);
    expect(parseText('Пейзаж\nКрасивые горы').draft, true);
  });
}
