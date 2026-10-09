import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/app_controller.dart';
import '../services/recipe_tools.dart';

Future<bool> saveRecipeWithDuplicateCheck(
  BuildContext context,
  AppController controller,
  Recipe recipe,
) async {
  Recipe next = recipe;
  final duplicates = controller.recipes.any((r) => r.id == recipe.id)
      ? <Recipe>[]
      : duplicateRecipes(recipe, controller.recipes);
  if (duplicates.isNotEmpty) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Похожий рецепт уже есть'),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Новый рецепт: «${recipe.title}». Можно обновить существующую карточку или сохранить отдельную. Фото, теги и заметки существующей карточки сохранятся.',
            ),
          ),
          for (final old in duplicates.take(5))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, old.id),
              child: Text('Обновить «${old.title}»'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'separate'),
            child: const Text('Сохранить отдельный рецепт'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    if (choice != 'separate') {
      next = mergeImportedRecipe(
        duplicates.firstWhere((r) => r.id == choice),
        recipe,
      );
    }
  }
  await controller.save(next);
  return true;
}
