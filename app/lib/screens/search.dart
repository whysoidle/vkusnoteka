import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_controller.dart';
import '../widgets/page_list.dart';
import '../widgets/recipe_card.dart';
import 'detail.dart';

/// A search route can cover an editor without discarding its unsaved fields.
class RecipeSearchScreen extends StatefulWidget {
  final AppController controller;
  const RecipeSearchScreen({super.key, required this.controller});
  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  final query = TextEditingController();
  final searchFocus = FocusNode();
  @override
  void dispose() {
    query.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      SingleActivator(
        LogicalKeyboardKey.keyF,
        meta: Theme.of(context).platform == TargetPlatform.macOS,
        control: Theme.of(context).platform == TargetPlatform.windows,
        includeRepeats: false,
      ): searchFocus.requestFocus,
      if (Theme.of(context).platform == TargetPlatform.macOS)
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          alt: true,
          includeRepeats: false,
        ): searchFocus.requestFocus,
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Поиск рецептов')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final text = query.text.trim().toLowerCase();
          final recipes = widget.controller.recipes
              .where(
                (r) =>
                    '${r.title} ${r.ingredients.join(' ')} ${r.notes} ${r.tags.join(' ')} ${r.collections.join(' ')}'
                        .toLowerCase()
                        .contains(text),
              )
              .toList();
          return PageList(
            maxWidth: 820,
            children: [
              TextField(
                autofocus: true,
                focusNode: searchFocus,
                controller: query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Блюдо или ингредиент',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 24),
              if (recipes.isEmpty) const Text('Рецепты не найдены'),
              for (final recipe in recipes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: RecipeCard(
                    recipe: recipe,
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeDetail(
                          recipe: recipe,
                          controller: widget.controller,
                        ),
                      ),
                    ),
                    onFavorite: () async {
                      try {
                        await widget.controller.save(
                          recipe.copyWith(favorite: !recipe.favorite),
                        );
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Не удалось обновить избранное.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
