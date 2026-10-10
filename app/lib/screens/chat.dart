import 'package:flutter/material.dart';
import '../widgets/recipe_text.dart';
import '../models/recipe.dart';
import '../services/app_controller.dart';
import '../services/import_service.dart';
import '../services/import_job.dart';
import '../services/local_recipe_ai.dart';
import '../services/text_parser.dart';
import '../widgets/count_label.dart';
import 'editor.dart';
import '../widgets/save_recipe.dart';
import '../services/document_import.dart';
import 'document_import.dart';
import '../theme/macos_glass.dart';
import '../widgets/desktop_swipe.dart';

class ChatMessage {
  final String text;
  final bool user;
  final List<Recipe> recipes;
  final List<String> warnings;
  final Set<String> saved = {};
  ChatMessage(
    this.text, {
    this.user = false,
    this.recipes = const [],
    this.warnings = const [],
  });
}

class ChatScreen extends StatefulWidget {
  final AppController controller;
  final TextEditingController composer;
  final FocusNode? composerFocus;
  final VoidCallback? onSettings;
  const ChatScreen({
    super.key,
    required this.controller,
    required this.composer,
    this.composerFocus,
    this.onSettings,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messages = <ChatMessage>[];
  final scroll = ScrollController();
  final importer = ImportService();
  bool busy = false;
  ImportJob? job;
  String progress = 'Разбираю рецепт…';
  @override
  void dispose() {
    job?.cancel();
    scroll.dispose();
    importer.client.close();
    super.dispose();
  }

  void scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });
  Recipe withDocument(Recipe recipe, DocumentText? document) {
    if (document == null) return recipe;
    return Recipe.fromJson({
      ...recipe.toJson(),
      'sourceUrl': document.sourceUrl.isEmpty
          ? recipe.sourceUrl
          : document.sourceUrl,
      'sourceText': 'Документ: ${document.name}\n\n${document.text}',
      'notes': [
        recipe.notes,
        ...document.warnings,
      ].where((s) => s.isNotEmpty).join('\n'),
    });
  }

  Future<void> attach() async {
    final document = await Navigator.push<DocumentText>(
      context,
      MaterialPageRoute(builder: (_) => const DocumentImportScreen()),
    );
    if (document == null || !mounted) return;
    widget.composer.text = document.text;
    await send(document: document);
  }

  Future<void> send({DocumentText? document}) async {
    final text = widget.composer.text.trim();
    if (text.isEmpty || busy) return;
    if (text.length > 50000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Текст слишком длинный. Максимум 50 000 символов.'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    widget.composer.clear();
    setState(() {
      busy = true;
      job = ImportJob();
      progress = 'Разбираю рецепт…';
      messages.add(ChatMessage(text, user: true));
    });
    scrollBottom();
    try {
      final result = await importer.parse(
        text,
        server: widget.controller.settings.server,
        token: widget.controller.importToken,
        localAi: LocalRecipeAi.supported && widget.controller.settings.localAi,
        job: job,
        onProgress: (text) {
          if (mounted) setState(() => progress = text);
        },
      );
      job?.check();
      if (!mounted) return;
      setState(
        () => messages.add(
          ChatMessage(
            result.recipes.any((r) => !r.draft)
                ? 'Рецепт разобран. Проверьте карточку и сохраните её в каталог.'
                : 'Карточка подготовлена. Можно заполнить вручную или сохранить черновик.',
            recipes: result.recipes
                .map((r) => withDocument(r, document))
                .toList(),
            warnings: [...result.warnings, ...?document?.warnings],
          ),
        ),
      );
    } on ImportCancelled {
      if (!mounted) return;
      final isUrl = RegExp(
        r'^https?://\S+$',
        caseSensitive: false,
      ).hasMatch(text);
      setState(
        () => messages.add(
          ChatMessage(
            'Разбор отменён. Источник оставлен для ручного заполнения.',
            recipes: [
              withDocument(
                isUrl
                    ? Recipe.blank(url: text, title: 'Рецепт по ссылке')
                    : parseText(text),
                document,
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final isUrl = RegExp(
        r'^https?://\S+$',
        caseSensitive: false,
      ).hasMatch(text);
      setState(
        () => messages.add(
          ChatMessage(
            'Источник сейчас недоступен. Ваш текст и ссылка сохранены в карточке для ручного заполнения.',
            recipes: [
              withDocument(
                isUrl
                    ? Recipe.blank(url: text, title: 'Рецепт по ссылке')
                    : parseText(text),
                document,
              ),
            ],
            warnings: [
              'Автоматический импорт не завершён. Заполните карточку или повторите импорт позже.',
            ],
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => busy = false);
        job = null;
        scrollBottom();
      }
    }
  }

  Future<void> editAndSave(
    ChatMessage message,
    Recipe recipe, {
    bool quickDraft = false,
  }) async {
    final updated = quickDraft
        ? recipe
        : await Navigator.push<Recipe>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RecipeEditor(recipe: recipe, warnings: message.warnings),
            ),
          );
    if (updated == null || !mounted) return;
    try {
      if (!await saveRecipeWithDuplicateCheck(
        context,
        widget.controller,
        updated,
      )) {
        return;
      }
      if (!mounted) return;
      setState(() => message.saved.add(recipe.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Рецепт сохранён в каталоге')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось записать рецепт. Карточка осталась в чате.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final glass = isMac(context) && !MacGlassPreferences.reduced(context);
    final desktop = isDesktopNavigation(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: desktop
                    ? c.primary.withValues(alpha: glass ? .10 : .08)
                    : c.primaryContainer,
                child: Icon(
                  Icons.auto_awesome_outlined,
                  color: desktop ? c.primary : c.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добавить рецепт',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Ссылка, видео или просто текст',
                      style: TextStyle(color: c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: c.secondaryContainer.withValues(
                          alpha: glass ? .48 : 1,
                        ),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 44,
                            color: c.onSecondaryContainer,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'Хорошие рецепты\nне должны теряться',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: c.onSecondaryContainer),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Пришлите рецепт сюда. Я оформлю ингредиенты и шаги, а вы сохраните карточку в свою книгу.',
                            style: TextStyle(
                              color: c.onSecondaryContainer,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Hint(
                      Icons.link,
                      'Ссылка на сайт',
                      'Рецепт будет извлечён со страницы',
                    ),
                    const _Hint(
                      Icons.play_circle_outline,
                      'Видео на YouTube',
                      'Описание и доступные субтитры',
                    ),
                    const _Hint(
                      Icons.notes_outlined,
                      'Текст рецепта',
                      'Можно вставить из заметок или сообщения',
                    ),
                    if (widget.controller.settings.server.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: TextButton.icon(
                          onPressed: widget.onSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(
                            LocalRecipeAi.supported
                                ? 'Настроить локальный ИИ'
                                : 'Подключить разбор субтитров',
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () {
                        widget.composer.text =
                            'Сырники\nИнгредиенты:\nТворог — 400 г\nЯйцо — 1 шт.\nМука — 3 ст. л.\nСахар — 2 ст. л.\nПриготовление:\nСмешайте творог, яйцо, муку и сахар.\nСформируйте сырники.\nОбжарьте с двух сторон до золотистой корочки.\nВремя: 20 минут\nПорции: 2';
                      },
                      child: const Text('Попробовать на примере'),
                    ),
                  ],
                )
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length + (busy ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: Text(progress)),
                            TextButton(
                              onPressed: job?.cancelled == true
                                  ? null
                                  : () {
                                      job?.cancel();
                                      setState(
                                        () => progress =
                                            'Останавливаю обработку…',
                                      );
                                    },
                              child: const Text('Отмена'),
                            ),
                          ],
                        ),
                      );
                    }
                    final m = messages[index];
                    return Align(
                      alignment: m.user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: const BoxConstraints(maxWidth: 640),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color:
                              (m.user
                                      ? c.primaryContainer
                                      : c.surfaceContainerLow)
                                  .withValues(alpha: glass ? .76 : 1),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RecipeText(
                              m.text,
                              style: TextStyle(
                                color: m.user
                                    ? c.onPrimaryContainer
                                    : c.onSurface,
                                height: 1.4,
                              ),
                            ),
                            ...m.recipes.map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 12),
                                    if (r.ingredients.isNotEmpty)
                                      Text(
                                        r.ingredients
                                            .take(5)
                                            .map((s) => '• $s')
                                            .join('\n'),
                                        style: const TextStyle(height: 1.5),
                                      ),
                                    if (r.steps.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          '${countLabel(r.steps.length, 'шаг', 'шага', 'шагов')} приготовления',
                                        ),
                                      ),
                                    if (r.sourceUrl.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                          r.sourceUrl,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: c.primary),
                                        ),
                                      ),
                                    const SizedBox(height: 14),
                                    if (m.saved.contains(r.id))
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text('В каталоге'),
                                        ],
                                      )
                                    else
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: () => editAndSave(m, r),
                                            icon: const Icon(Icons.edit_note),
                                            label: Text(
                                              r.draft
                                                  ? 'Заполнить вручную'
                                                  : 'Проверить и сохранить',
                                            ),
                                          ),
                                          if (r.draft)
                                            TextButton(
                                              onPressed: () => editAndSave(
                                                m,
                                                r,
                                                quickDraft: true,
                                              ),
                                              child: const Text(
                                                'Сохранить черновик',
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (m.warnings.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  m.warnings.join('\n'),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: c.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: busy ? null : attach,
                tooltip: 'Скриншот, фото или PDF',
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: widget.composer,
                  focusNode: widget.composerFocus,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Вставьте ссылку или рецепт…',
                    contentPadding: EdgeInsets.all(18),
                  ),
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                width: 56,
                child: IconButton.filled(
                  onPressed: busy ? null : send,
                  tooltip: 'Разобрать рецепт',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _Hint(this.icon, this.title, this.subtitle);
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    subtitle: Text(subtitle),
  );
}
