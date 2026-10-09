import 'package:flutter/material.dart';
import '../widgets/recipe_text.dart';
import '../models/recipe.dart';
import '../services/photos.dart';
import '../widgets/recipe_photo.dart';

class RecipeEditor extends StatefulWidget {
  final Recipe recipe;
  final List<String> warnings;
  const RecipeEditor({
    super.key,
    required this.recipe,
    this.warnings = const [],
  });
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController title,
      ingredients,
      steps,
      servings,
      time,
      notes,
      source,
      tags,
      collections;
  late String category, photo;
  bool photoBusy = false;
  late bool draft;
  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    title = TextEditingController(text: r.title);
    ingredients = TextEditingController(text: r.ingredients.join('\n'));
    steps = TextEditingController(text: r.steps.join('\n'));
    servings = TextEditingController(text: r.servings);
    time = TextEditingController(text: r.time);
    notes = TextEditingController(text: r.notes);
    source = TextEditingController(text: r.sourceUrl);
    category = r.category;
    photo = r.photo;
    tags = TextEditingController(text: r.tags.join(', '));
    collections = TextEditingController(text: r.collections.join(', '));
    draft = r.draft;
  }

  @override
  void dispose() {
    for (final c in [
      title,
      ingredients,
      steps,
      servings,
      time,
      notes,
      source,
      tags,
      collections,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> lines(TextEditingController c) => c.text
      .split('\n')
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toList();
  void save() {
    if (!_form.currentState!.validate()) return;
    final ingredientList = lines(ingredients), stepList = lines(steps);
    if (!draft && (ingredientList.isEmpty || stepList.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Добавьте ингредиенты и шаги или сохраните как черновик.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      Recipe(
        id: widget.recipe.id,
        title: title.text.trim(),
        ingredients: ingredientList,
        steps: stepList,
        category: category,
        servings: servings.text.trim(),
        time: time.text.trim(),
        notes: notes.text.trim(),
        sourceUrl: source.text.trim(),
        sourceText: widget.recipe.sourceText,
        photo: photo,
        tags: tags.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(),
        collections: collections.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList(),
        favorite: widget.recipe.favorite,
        draft: draft,
      ),
    );
  }

  Future<void> choosePhoto() async {
    setState(() => photoBusy = true);
    try {
      final picked = await pickRecipePhoto();
      if (picked != null && mounted) setState(() => photo = picked);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Не удалось прочитать фотографию',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Карточка рецепта'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: save,
              icon: const Icon(Icons.check),
              label: const Text('Сохранить'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (widget.warnings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: c.tertiaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        widget.warnings.join('\n\n'),
                        style: TextStyle(color: c.onTertiaryContainer),
                      ),
                    ),
                  ),
                if (photo.isNotEmpty) ...[
                  RecipePhoto(photo: photo, height: 200),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: photoBusy ? null : choosePhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        photoBusy ? 'Подготавливаю фото…' : 'Фото блюда',
                      ),
                    ),
                    if (photo.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => photo = ''),
                        child: const Text('Убрать фото'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(
                    labelText: 'Название блюда',
                  ),
                  validator: (s) =>
                      s == null || s.trim().isEmpty ? 'Введите название' : null,
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: {...categories, category}
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: time,
                        decoration: const InputDecoration(
                          labelText: 'Время',
                          hintText: '30 минут',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: servings,
                        decoration: const InputDecoration(
                          labelText: 'Порции',
                          hintText: '2 порции',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Ингредиенты',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: ingredients,
                  minLines: 4,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  decoration: const InputDecoration(
                    hintText:
                        'Каждый ингредиент — с новой строки\nМука — 200 г\nЯйца — 2 шт.',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Приготовление',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: steps,
                  minLines: 4,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  decoration: const InputDecoration(
                    hintText:
                        'Каждый шаг — с новой строки\nСмешайте ингредиенты.\nВыпекайте 20 минут.',
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Теги через запятую',
                    hintText: 'Без мяса, Быстро, Для гостей',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: collections,
                  decoration: const InputDecoration(
                    labelText: 'Подборки через запятую',
                    hintText: 'На каждый день, Хочу приготовить',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final name in [
                      'На каждый день',
                      'До 30 минут',
                      'Хочу приготовить',
                    ])
                      FilterChip(
                        label: Text(name),
                        selected: collections.text
                            .split(',')
                            .map((s) => s.trim())
                            .contains(name),
                        onSelected: (selected) {
                          final names = collections.text
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toSet();
                          selected ? names.add(name) : names.remove(name);
                          setState(() => collections.text = names.join(', '));
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: notes,
                  minLines: 2,
                  maxLines: null,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  decoration: const InputDecoration(labelText: 'Заметки'),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'Ссылка на источник',
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: (s) {
                    if (widget.recipe.sourceUrl.isNotEmpty &&
                        (s == null || s.trim().isEmpty)) {
                      return 'Сохраните ссылку на исходный рецепт';
                    }
                    if (s == null || s.trim().isEmpty) return null;
                    final uri = Uri.tryParse(s.trim());
                    return uri != null &&
                            ['https', 'http'].contains(uri.scheme) &&
                            uri.host.isNotEmpty
                        ? null
                        : 'Нужна ссылка http:// или https://';
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Сохранить как черновик'),
                  subtitle: const Text(
                    'Можно оставить только ссылку и заполнить позже',
                  ),
                  value: draft,
                  onChanged: (v) => setState(() => draft = v),
                ),
                if (widget.recipe.sourceText.isNotEmpty)
                  ExpansionTile(
                    title: const Text('Исходный текст'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: RecipeText(widget.recipe.sourceText),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Сохранить в каталог'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
