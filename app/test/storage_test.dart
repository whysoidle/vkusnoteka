import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_vault/models/recipe.dart';
import 'package:recipe_vault/services/storage.dart';

void main() {
  test(
    'an interrupted write recovers a complete database and preserves Unicode',
    () async {
      final temp = await Directory.systemTemp.createTemp('recipe-storage-');
      addTearDown(() => temp.delete(recursive: true));
      final store = LocalStorage(temp);
      final db = RecipeDatabase()..put(Recipe.blank(title: 'Борщ'), 'android');
      await store.saveDatabase(db);
      final updated = RecipeDatabase(db.records)
        ..put(Recipe.blank(title: 'Сырники'), 'android');
      await File(
        '${store.databaseFile.path}.pending',
      ).writeAsString(updated.encode());
      await store.databaseFile.rename('${store.databaseFile.path}.bak');
      expect((await store.loadDatabase()).recipes.length, 2);
    },
  );
  test(
    'a corrupt main file falls back to a backup, never an empty catalog',
    () async {
      final temp = await Directory.systemTemp.createTemp('recipe-storage-');
      addTearDown(() => temp.delete(recursive: true));
      final store = LocalStorage(temp);
      final db = RecipeDatabase()..put(Recipe.blank(title: 'Борщ'), 'android');
      await File('${store.databaseFile.path}.bak').writeAsString(db.encode());
      await store.databaseFile.writeAsString('{');
      expect((await store.loadDatabase()).recipes.single.title, 'Борщ');
      await File('${store.databaseFile.path}.bak').delete();
      expect(store.loadDatabase(), throwsFormatException);
    },
  );
}
