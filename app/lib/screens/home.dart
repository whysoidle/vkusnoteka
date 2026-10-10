import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/recipe.dart';
import '../services/app_controller.dart';
import '../widgets/recipe_card.dart';
import '../widgets/count_label.dart';
import 'chat.dart';
import 'detail.dart';
import 'editor.dart';
import 'settings.dart';
import '../widgets/save_recipe.dart';
import '../services/recipe_tools.dart';
import '../theme/macos_glass.dart';
import '../widgets/mac_home_shell.dart';
import '../widgets/mac_motion.dart';
import '../branding.dart';
import '../widgets/desktop_swipe.dart';
import 'search.dart';

class HomeScreen extends StatefulWidget {
  final AppController controller;
  const HomeScreen({super.key, required this.controller});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final composer = TextEditingController(), search = TextEditingController();
  final searchFocus = FocusNode();
  final importFocus = FocusNode();
  int tab = 0;
  bool showFilters = false;
  int? maxMinutes;
  String tag = '', collection = '';
  final ingredientSearch = TextEditingController(),
      excludeSearch = TextEditingController();
  String filter = 'Все рецепты', category = 'Все';
  static const share = MethodChannel('recipe_vault/share');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.autoSync();
    share.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') receive(call.arguments as String);
    });
    share
        .invokeMethod<String>('initialText')
        .then((text) {
          if (text != null && text.isNotEmpty && mounted) receive(text);
        })
        .catchError((Object _) {});
  }

  void receive(String text) {
    if (mounted) {
      setState(() {
        composer.text = text;
        tab = 1;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.autoSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    share.setMethodCallHandler(null);
    composer.dispose();
    search.dispose();
    searchFocus.dispose();
    importFocus.dispose();
    ingredientSearch.dispose();
    excludeSearch.dispose();
    super.dispose();
  }

  void settings() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SettingsScreen(controller: widget.controller),
    ),
  );
  bool adding = false;
  void searchCatalog() {
    if (ModalRoute.of(context)?.isCurrent != true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeSearchScreen(controller: widget.controller),
        ),
      );
      return;
    }
    setState(() => tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocus.requestFocus();
    });
  }

  Future<void> add() async {
    if (adding) return;
    adding = true;
    final recipe = await Navigator.push<Recipe>(
      context,
      MaterialPageRoute(builder: (_) => RecipeEditor(recipe: Recipe.blank())),
    );
    adding = false;
    if (recipe == null) return;
    try {
      if (!mounted) return;
      await saveRecipeWithDuplicateCheck(context, widget.controller, recipe);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить рецепт.')),
        );
      }
    }
  }

  void open(Recipe r) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RecipeDetail(recipe: r, controller: widget.controller),
    ),
  );
  Future<void> favorite(Recipe r) async {
    try {
      await widget.controller.save(r.copyWith(favorite: !r.favorite));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить избранное.')),
        );
      }
    }
  }

  Widget catalog() {
    final c = Theme.of(context).colorScheme,
        recipes = widget.controller.recipes;
    final q = search.text.trim().toLowerCase();
    final filtered = recipes
        .where(
          (r) =>
              (category == 'Все' || r.category == category) &&
              (filter != 'Избранное' || r.favorite) &&
              (filter != 'Черновики' || r.draft) &&
              (tag.isEmpty || r.tags.contains(tag)) &&
              (collection.isEmpty ||
                  r.collections.contains(collection) ||
                  collection == 'До 30 минут' &&
                      recipeMinutes(r.time) != null &&
                      recipeMinutes(r.time)! <= 30) &&
              (maxMinutes == null ||
                  recipeMinutes(r.time) != null &&
                      recipeMinutes(r.time)! <= maxMinutes!) &&
              ingredientSearch.text
                  .split(',')
                  .map((s) => normalizeWords(s))
                  .where((s) => s.isNotEmpty)
                  .every(
                    (s) => normalizeWords(r.ingredients.join(' ')).contains(s),
                  ) &&
              !excludeSearch.text
                  .split(',')
                  .map((s) => normalizeWords(s))
                  .where((s) => s.isNotEmpty)
                  .any(
                    (s) => normalizeWords(r.ingredients.join(' ')).contains(s),
                  ) &&
              (q.isEmpty ||
                  '${r.title} ${r.ingredients.join(' ')} ${r.notes} ${r.tags.join(' ')} ${r.collections.join(' ')}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
    return CustomScrollView(
      slivers: [
        if (isMac(context))
          Builder(
            builder: (context) => SliverToBoxAdapter(
              child: SizedBox(height: MacCatalogInset.of(context)),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: MacAnimatedSize(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMac(context)
                                  ? 'Ваша книга рецептов'
                                  : 'Ваша книга\nрецептов',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${countLabel(recipes.length, 'рецепт', 'рецепта', 'рецептов')} · всё любимое под рукой',
                              style: TextStyle(color: c.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: add,
                        tooltip: 'Добавить вручную',
                        icon: const Icon(Icons.add),
                        padding: const EdgeInsets.all(18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: search,
                    focusNode: searchFocus,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Блюдо или ингредиент',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                search.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  DesktopSwipe(
                    blockNavigation: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final value in [
                            'Все рецепты',
                            'Избранное',
                            'Черновики',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                selected: filter == value,
                                label: Text(value),
                                onSelected: (_) =>
                                    setState(() => filter = value),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DesktopSwipe(
                    blockNavigation: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final value in [
                            'Все',
                            ...{
                              ...categories.where((c) => c != 'Без категории'),
                              ...recipes.map((r) => r.category),
                            },
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                selected: category == value,
                                label: Text(value),
                                onSelected: (_) =>
                                    setState(() => category = value),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DesktopSwipe(
                    blockNavigation: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final name in {
                            '',
                            'На каждый день',
                            'До 30 минут',
                            'Хочу приготовить',
                            ...recipes.expand((r) => r.collections),
                          })
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  name.isEmpty ? 'Все подборки' : name,
                                ),
                                selected: collection == name,
                                onSelected: (_) =>
                                    setState(() => collection = name),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => showFilters = !showFilters),
                      icon: const Icon(Icons.tune),
                      label: const Text('Фильтры по времени и ингредиентам'),
                    ),
                  ),
                  if (showFilters) ...[
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final minutes in [null, 15, 30, 60])
                          ChoiceChip(
                            label: Text(
                              minutes == null
                                  ? 'Любое время'
                                  : 'До $minutes мин',
                            ),
                            selected: maxMinutes == minutes,
                            onSelected: (_) =>
                                setState(() => maxMinutes = minutes),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ingredientSearch,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Есть ингредиенты',
                        hintText: 'Молоко, мука',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: excludeSearch,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Без ингредиентов',
                        hintText: 'Грибы, орехи',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Все теги'),
                          selected: tag.isEmpty,
                          onSelected: (_) => setState(() => tag = ''),
                        ),
                        for (final name
                            in recipes.expand((r) => r.tags).toSet())
                          ChoiceChip(
                            label: Text(name),
                            selected: tag == name,
                            onSelected: (_) => setState(() => tag = name),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        ingredientSearch.clear();
                        excludeSearch.clear();
                        tag = '';
                        maxMinutes = null;
                        collection = '';
                      }),
                      child: const Text('Сбросить фильтры'),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: c.secondaryContainer,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Icon(
                      Icons.menu_book_outlined,
                      size: 64,
                      color: c.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    recipes.isEmpty
                        ? 'Первый рецепт — начало книги'
                        : 'Рецепты не найдены',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recipes.isEmpty
                        ? 'Отправьте ссылку или текст в чат.\nЛюбимые блюда будут ждать здесь.'
                        : 'Попробуйте другой запрос или категорию.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => setState(() => tab = 1),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Добавить через чат'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent > 780
                    ? 3
                    : constraints.crossAxisExtent > 530
                    ? 2
                    : 1;
                // Wrap uses natural card heights so large text and long metadata never overflow.
                final width =
                    (constraints.crossAxisExtent - (columns - 1) * 16) /
                    columns;
                return SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: filtered
                        .map(
                          (r) => SizedBox(
                            width: width,
                            child: RecipeCard(
                              recipe: r,
                              onOpen: () => open(r),
                              onFavorite: () => favorite(r),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100,
            rail = constraints.maxWidth >= 720;
        final chat = ChatScreen(
          key: const ValueKey('chat'),
          controller: widget.controller,
          composer: composer,
          composerFocus: isMac(context) ? importFocus : null,
          onSettings: settings,
        );
        final c = Theme.of(context).colorScheme;
        if (isMac(context)) {
          return DesktopSwipe(
            onLeft: () => setState(() => tab = 1),
            onRight: () => setState(() => tab = 0),
            child: MacHomeShell(
              controller: widget.controller,
              catalog: catalog(),
              chat: chat,
              tab: tab,
              filter: filter,
              collection: collection,
              onTab: (value) {
                setState(() => tab = value);
                if (value == 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) importFocus.requestFocus();
                  });
                }
              },
              onFilter: (value) => setState(() => filter = value),
              onCollection: (value) => setState(() => collection = value),
              onAdd: add,
              onSettings: settings,
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                AppLogo(),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: widget.controller.syncing
                    ? null
                    : widget.controller.sync,
                tooltip: widget.controller.syncMessage.isEmpty
                    ? 'Синхронизировать с Яндекс Диском'
                    : widget.controller.syncMessage,
                icon: widget.controller.syncing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
              ),
              IconButton(
                onPressed: settings,
                tooltip: 'Настройки',
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (widget.controller.syncMessage.isNotEmpty &&
                    widget.controller.syncMessage != 'Синхронизировано')
                  MaterialBanner(
                    content: Text(widget.controller.syncMessage),
                    actions: [
                      TextButton(
                        onPressed: widget.controller.syncing
                            ? null
                            : widget.controller.sync,
                        child: const Text('Повторить'),
                      ),
                      TextButton(
                        onPressed: settings,
                        child: const Text('Настройки'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (rail)
                        NavigationRail(
                          selectedIndex: tab,
                          labelType: NavigationRailLabelType.all,
                          onDestinationSelected: (v) => setState(() => tab = v),
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.grid_view_outlined),
                              selectedIcon: Icon(Icons.grid_view_rounded),
                              label: Text('Каталог'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.chat_bubble_outline),
                              selectedIcon: Icon(Icons.chat_bubble),
                              label: Text('Чат'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: wide
                            ? Row(
                                children: [
                                  Expanded(child: catalog()),
                                  Container(width: 1, color: c.outlineVariant),
                                  SizedBox(width: 410, child: chat),
                                ],
                              )
                            : DesktopSwipe(
                                onLeft: () => setState(() => tab = 1),
                                onRight: () => setState(() => tab = 0),
                                child: IndexedStack(
                                  index: tab,
                                  children: [catalog(), chat],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: rail
              ? null
              : NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (v) => setState(() => tab = v),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_outlined),
                      selectedIcon: Icon(Icons.grid_view_rounded),
                      label: 'Каталог',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: 'Чат',
                    ),
                  ],
                ),
        );
      },
    ),
  );
}
