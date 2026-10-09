import 'package:flutter/material.dart';
import '../models/recipe.dart';
import 'count_label.dart';
import 'recipe_photo.dart';
import '../theme/macos_glass.dart';
import 'mac_motion.dart';

IconData categoryIcon(String category) => switch (category) {
  'Завтраки' => Icons.egg_alt_outlined,
  'Супы' => Icons.soup_kitchen_outlined,
  'Салаты' => Icons.eco_outlined,
  'Выпечка' => Icons.bakery_dining_outlined,
  'Десерты' => Icons.cake_outlined,
  'Напитки' => Icons.local_cafe_outlined,
  _ => Icons.restaurant_outlined,
};

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onOpen, onFavorite;
  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onOpen,
    required this.onFavorite,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final favoriteIcon = Icon(
      recipe.favorite ? Icons.favorite : Icons.favorite_border,
      key: ValueKey(recipe.favorite),
      color: recipe.favorite ? c.primary : c.onSurfaceVariant,
    );
    final card = Card(
      color: isMac(context) ? null : c.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recipe.photo.isNotEmpty) ...[
                RecipePhoto(photo: recipe.photo),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      categoryIcon(recipe.category),
                      color: c.onSecondaryContainer,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onFavorite,
                    tooltip: recipe.favorite
                        ? 'Убрать из избранного'
                        : 'В избранное',
                    icon: isMac(context)
                        ? AnimatedSwitcher(
                            duration: MacMotion.duration(context, 180),
                            switchInCurve: MacMotion.curve,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                            child: favoriteIcon,
                          )
                        : favoriteIcon,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                recipe.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                recipe.category,
                style: TextStyle(color: c.onSurfaceVariant),
              ),
              if (recipe.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    recipe.tags.take(3).map((s) => '#$s').join(' · '),
                    style: TextStyle(color: c.primary),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (recipe.time.isNotEmpty)
                    _Meta(Icons.schedule, recipe.time),
                  if (recipe.servings.isNotEmpty)
                    _Meta(Icons.people_outline, recipe.servings),
                  if (recipe.draft)
                    const _Meta(Icons.edit_note, 'Черновик')
                  else
                    _Meta(
                      Icons.checklist,
                      countLabel(
                        recipe.ingredients.length,
                        'ингредиент',
                        'ингредиента',
                        'ингредиентов',
                      ),
                    ),
                  if (recipe.sourceUrl.contains('youtu'))
                    const _Meta(Icons.play_circle_outline, 'YouTube'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return isMac(context) ? MacHoverFeedback(child: card) : card;
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
