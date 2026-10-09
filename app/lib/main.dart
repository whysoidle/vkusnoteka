import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home.dart';
import 'services/app_controller.dart';
import 'services/storage.dart';
import 'theme/appearance.dart';
import 'theme/macos_glass.dart';
import 'branding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final storage = await LocalStorage.open();
    final controller = AppController(
      storage: storage,
      database: await storage.loadDatabase(),
      settings: await storage.loadSettings(),
    );
    await controller.initialize();
    runApp(RecipeVaultApp(controller: controller));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: SelectableText(
                'Не удалось открыть Вкуснотеку.\n\n$e\n\nИсходные файлы не удалены.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RecipeVaultApp extends StatelessWidget {
  final AppController controller;
  const RecipeVaultApp({super.key, required this.controller});
  ThemeData theme(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: .55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
    return base.platform == TargetPlatform.macOS ? macTheme(base) : base;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => DynamicColorBuilder(
      builder: (light, dark) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        scrollBehavior: const RecipeScrollBehavior(),
        builder: (context, child) => isMac(context)
            ? MacGlassEnvironment(child: MacWindowBackground(child: child!))
            : child!,
        theme: theme(
          appColorScheme(controller.settings.accent, Brightness.light, light),
        ),
        darkTheme: theme(
          appColorScheme(controller.settings.accent, Brightness.dark, dark),
        ),
        themeMode: switch (controller.settings.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: HomeScreen(controller: controller),
      ),
    ),
  );
}
