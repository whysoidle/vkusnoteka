import 'package:flutter/material.dart';
import '../widgets/recipe_text.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recipe.dart';
import '../services/app_controller.dart';
import 'editor.dart';
import 'cooking.dart';
import '../services/recipe_tools.dart';
import '../widgets/recipe_photo.dart';

class RecipeDetail extends StatefulWidget {
  final Recipe recipe;
  final AppController controller;
  const RecipeDetail({
    super.key,
    required this.recipe,
    required this.controller,
  });
  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  late Recipe recipe;
  final checked = <int>{};
  double? portions;
  @override
  void initState() {
    super.initState();
    recipe = widget.recipe;
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> edit() async {
    final edited = await Navigator.push<Recipe>(
      context,
      MaterialPageRoute(builder: (_) => RecipeEditor(recipe: recipe)),
    );
    if (edited == null) return;
    try {
      await widget.controller.save(edited);
      if (mounted) {
        setState(() {
          recipe = edited;
          portions = null;
          checked.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        message('Не удалось сохранить рецепт. Проверьте свободное место.');
      }
    }
  }

  Future<void> delete() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить рецепт?'),
        content: Text(
          '«${recipe.title}» будет удалён из каталога и при синхронизации с других устройств.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await widget.controller.remove(recipe);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) message('Не удалось удалить рецепт.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: edit,
            tooltip: 'Редактировать',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: delete,
            tooltip: 'Удалить',
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            children: [
              if (recipe.photo.isNotEmpty) ...[
                RecipePhoto(photo: recipe.photo, height: 220),
                const SizedBox(height: 20),
              ],
              Text(
                recipe.category.toUpperCase(),
                style: TextStyle(color: c.primary, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                recipe.title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: [
                  if (recipe.time.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: Text(recipe.time),
                    ),
                  if (recipe.servings.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.people_outline, size: 18),
                      label: Text(recipe.servings),
                    ),
                  if (recipe.draft)
                    const Chip(
                      avatar: Icon(Icons.edit_note, size: 18),
                      label: Text('Черновик'),
                    ),
                ],
              ),
              if (recipe.tags.isNotEmpty || recipe.collections.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    ...recipe.tags,
                    ...recipe.collections,
                  ].map((s) => Chip(label: Text(s))).toList(),
                ),
              if (parseServings(recipe.servings) != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Text('Количество порций')),
                    IconButton(
                      tooltip: 'Меньше порций',
                      onPressed:
                          (portions ?? parseServings(recipe.servings)!) <= 1
                          ? null
                          : () => setState(
                              () => portions =
                                  (portions ??
                                      parseServings(recipe.servings)!) -
                                  1,
                            ),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      formatQuantity(
                        portions ?? parseServings(recipe.servings)!,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Больше порций',
                      onPressed:
                          (portions ?? parseServings(recipe.servings)!) >= 100
                          ? null
                          : () => setState(
                              () => portions =
                                  (portions ??
                                      parseServings(recipe.servings)!) +
                                  1,
                            ),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Исходные порции',
                      onPressed: () => setState(() => portions = null),
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),
                Text(
                  'Исходный рецепт: ${recipe.servings}. Пересчитываются распознанные количества; остальные проверьте вручную.',
                ),
              ],
              if (recipe.steps.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CookingScreen(recipe: recipe),
                      ),
                    ),
                    icon: const Icon(Icons.restaurant),
                    label: const Text('Начать готовить'),
                  ),
                ),
              if (recipe.sourceUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    color: c.secondaryContainer,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      leading: const Icon(Icons.open_in_new),
                      title: Text(
                        recipe.sourceUrl.contains('youtu')
                            ? 'Открыть видео на YouTube'
                            : 'Открыть источник',
                      ),
                      subtitle: Text(
                        recipe.sourceUrl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        try {
                          final uri = Uri.parse(recipe.sourceUrl);
                          if (!['http', 'https'].contains(uri.scheme) ||
                              !await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              )) {
                            if (mounted) message('Не удалось открыть ссылку.');
                          }
                        } catch (_) {
                          if (mounted) message('Не удалось открыть ссылку.');
                        }
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 30),
              Text(
                'Ингредиенты',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              if (recipe.ingredients.isEmpty)
                const Text('Пока не заполнены. Добавьте их в редакторе.'),
              ...recipe.ingredients.asMap().entries.map(
                (e) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary:
                      e.value.contains('количество не указано') ||
                          e.value.contains('?')
                      ? const Tooltip(
                          message: 'Количество нужно проверить',
                          child: Icon(Icons.help_outline),
                        )
                      : null,
                  title: Text(
                    portions == null
                        ? e.value
                        : scaleIngredient(
                            e.value,
                            portions! / parseServings(recipe.servings)!,
                          ),
                    style: TextStyle(
                      decoration: checked.contains(e.key)
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  value: checked.contains(e.key),
                  onChanged: (v) => setState(() {
                    v == true ? checked.add(e.key) : checked.remove(e.key);
                  }),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'Приготовление',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              if (recipe.steps.isEmpty)
                const Text(
                  'Пока не заполнено. Ссылку можно оставить и вернуться позже.',
                ),
              ...recipe.steps.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: c.primaryContainer,
                        foregroundColor: c.onPrimaryContainer,
                        child: Text('${e.key + 1}'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: RecipeText(e.value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (recipe.notes.isNotEmpty)
                Card(
                  color: c.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Заметки',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        RecipeText(recipe.notes),
                      ],
                    ),
                  ),
                ),
              if (recipe.draft)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: FilledButton.icon(
                    onPressed: edit,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Заполнить рецепт'),
                  ),
                ),
              if (recipe.sourceText.isNotEmpty)
                ExpansionTile(
                  title: const Text('Исходный текст'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: RecipeText(recipe.sourceText),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
