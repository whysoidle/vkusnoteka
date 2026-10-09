import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_controller.dart';
import '../theme/macos_glass.dart';
import 'mac_motion.dart';
import '../branding.dart';

class MacHomeShell extends StatelessWidget {
  final AppController controller;
  final Widget catalog, chat;
  final int tab;
  final String filter, collection;
  final ValueChanged<int> onTab;
  final ValueChanged<String> onFilter, onCollection;
  final VoidCallback onAdd, onSettings, onSearch;
  const MacHomeShell({
    super.key,
    required this.controller,
    required this.catalog,
    required this.chat,
    required this.tab,
    required this.filter,
    required this.collection,
    required this.onTab,
    required this.onFilter,
    required this.onCollection,
    required this.onAdd,
    required this.onSettings,
    required this.onSearch,
  });

  Widget destination(
    BuildContext context,
    String label,
    IconData icon,
    bool selected,
    VoidCallback action, {
    String? trailing,
  }) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MacHoverFeedback(
        lift: false,
        child: AnimatedContainer(
          duration: MacMotion.duration(context, 180),
          curve: MacMotion.curve,
          decoration: BoxDecoration(
            color: selected ? null : Colors.transparent,
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      c.primary.withValues(alpha: .22),
                      c.primary.withValues(alpha: .09),
                    ],
                  )
                : null,
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: .26))
                : null,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              leading: Icon(
                icon,
                size: 20,
                color: selected ? c.primary : c.onSurfaceVariant,
              ),
              title: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              trailing: trailing == null
                  ? null
                  : Text(
                      trailing,
                      style: TextStyle(color: c.onSurfaceVariant, fontSize: 12),
                    ),
              onTap: action,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): onAdd,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onSearch,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): onSettings,
      const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
          onTab(0),
      const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
          onTab(1),
    },
    child: Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidebar = constraints.maxWidth >= 860;
          // Import is a destination in its own right even when the catalog
          // normally has a chat pane alongside it.
          final split = constraints.maxWidth >= 1320 && tab == 0;
          final c = Theme.of(context).colorScheme;
          final contentWidth = constraints.maxWidth - 24 - (sidebar ? 230 : 0);
          final toolbarExtent =
              64.0 +
              (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 42);
          final hasSyncWarning =
              controller.syncMessage.isNotEmpty &&
              controller.syncMessage != 'Синхронизировано';
          final toolbar = GlassPanel(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: MacMotion.duration(context, 160),
                    switchInCurve: MacMotion.curve,
                    layoutBuilder: (child, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?child],
                    ),
                    child: Text(
                      tab == 0 ? 'Моя книга' : 'Импорт рецепта',
                      key: ValueKey(tab),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (!sidebar)
                  IconButton(
                    onPressed: () => onTab(tab == 0 ? 1 : 0),
                    tooltip: tab == 0 ? 'Чат' : 'Каталог',
                    icon: Icon(
                      tab == 0
                          ? Icons.auto_awesome_outlined
                          : Icons.grid_view_outlined,
                    ),
                  ),
                IconButton(
                  onPressed: controller.syncing ? null : controller.sync,
                  tooltip: controller.syncMessage.isEmpty
                      ? 'Синхронизировать с Яндекс Диском'
                      : controller.syncMessage,
                  icon: controller.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined, size: 20),
                ),
                if (!sidebar)
                  IconButton(
                    onPressed: onSettings,
                    tooltip: 'Настройки',
                    icon: const Icon(Icons.settings_outlined),
                  ),
                const SizedBox(width: 8),
                MacHoverFeedback(
                  lift: false,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Новый рецепт'),
                  ),
                ),
              ],
            ),
          );
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  if (sidebar) ...[
                    SizedBox(
                      width: 218,
                      child: GlassPanel(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                14,
                                10,
                                26,
                              ),
                              child: Row(
                                children: [
                                  const AppLogo(size: 28),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      appName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                children: [
                                  destination(
                                    context,
                                    'Все рецепты',
                                    Icons.grid_view_rounded,
                                    tab == 0 &&
                                        filter == 'Все рецепты' &&
                                        collection.isEmpty,
                                    () {
                                      onFilter('Все рецепты');
                                      onCollection('');
                                      onTab(0);
                                    },
                                    trailing: '${controller.recipes.length}',
                                  ),
                                  destination(
                                    context,
                                    'Избранное',
                                    Icons.favorite_border,
                                    tab == 0 && filter == 'Избранное',
                                    () {
                                      onFilter('Избранное');
                                      onCollection('');
                                      onTab(0);
                                    },
                                  ),
                                  destination(
                                    context,
                                    'Черновики',
                                    Icons.edit_note,
                                    tab == 0 && filter == 'Черновики',
                                    () {
                                      onFilter('Черновики');
                                      onCollection('');
                                      onTab(0);
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      left: 12,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      'ПОДБОРКИ',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  ),
                                  for (final name in {
                                    'На каждый день',
                                    'До 30 минут',
                                    'Хочу приготовить',
                                    ...controller.recipes.expand(
                                      (r) => r.collections,
                                    ),
                                  })
                                    destination(
                                      context,
                                      name,
                                      Icons.folder_outlined,
                                      tab == 0 && collection == name,
                                      () {
                                        onFilter('Все рецепты');
                                        onCollection(name);
                                        onTab(0);
                                      },
                                    ),
                                  const SizedBox(height: 20),
                                  destination(
                                    context,
                                    'Импорт рецепта',
                                    Icons.auto_awesome_outlined,
                                    tab == 1,
                                    () => onTab(1),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 24),
                            destination(
                              context,
                              'Настройки',
                              Icons.settings_outlined,
                              false,
                              onSettings,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                              child: Text(
                                '⌘ N  Новый рецепт\n⌘ F  Поиск',
                                style: TextStyle(
                                  color: c.onSurfaceVariant,
                                  fontSize: 11,
                                  height: 1.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            if (hasSyncWarning)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: toolbarExtent + 8,
                                  bottom: 12,
                                ),
                                child: MaterialBanner(
                                  content: Text(controller.syncMessage),
                                  actions: [
                                    TextButton(
                                      onPressed: controller.syncing
                                          ? null
                                          : controller.sync,
                                      child: const Text('Повторить'),
                                    ),
                                    TextButton(
                                      onPressed: onSettings,
                                      child: const Text('Настройки'),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  MacAnimatedExtent(
                                    value: split ? 402 : 0,
                                    builder: (context, right, child) =>
                                        Positioned.fill(
                                          right: right,
                                          child: child,
                                        ),
                                    child: MacPaneVisibility(
                                      visible: split || tab == 0,
                                      child: MacCatalogInset(
                                        top: hasSyncWarning ? 0 : toolbarExtent,
                                        child: catalog,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    top: hasSyncWarning ? 0 : toolbarExtent,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: MacAnimatedExtent(
                                        value: split ? 390 : contentWidth,
                                        builder: (context, width, child) =>
                                            SizedBox(
                                              width: width,
                                              height: double.infinity,
                                              child: child,
                                            ),
                                        child: MacPaneVisibility(
                                          visible: split || tab == 1,
                                          child: GlassPanel(child: chat),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SizedBox(
                            height: toolbarExtent - 12,
                            child: toolbar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// This spacer belongs to the scrollable content, so it scrolls away while the
/// toolbar remains above the viewport and samples the content behind it.
class MacCatalogInset extends InheritedWidget {
  final double top;
  const MacCatalogInset({super.key, required this.top, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MacCatalogInset>()?.top ?? 0;

  @override
  bool updateShouldNotify(MacCatalogInset oldWidget) => top != oldWidget.top;
}
