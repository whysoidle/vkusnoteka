import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/recipe_text.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/recipe.dart';
import '../services/app_controller.dart';
import '../services/storage.dart';
import '../services/local_recipe_ai.dart';
import '../widgets/local_ai_settings.dart';
import '../theme/appearance.dart';
import '../services/yandex_auth.dart';

class SettingsScreen extends StatefulWidget {
  final AppController controller;
  const SettingsScreen({super.key, required this.controller});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController server,
      diskToken,
      folder,
      apiToken,
      clientId,
      webDavLogin,
      webDavPassword;
  late bool autoSync, localAi;
  late String theme, accent, syncMethod;
  Timer? textDebounce;
  String saveError = '';
  bool busy = false, diskTokenEdited = false, webDavPasswordEdited = false;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    final a = widget.controller;
    webDavLogin = TextEditingController(text: a.settings.yandexLogin);
    webDavPassword = TextEditingController(text: a.webDavPassword);
    syncMethod = a.settings.syncMethod;
    clientId = TextEditingController(text: a.settings.yandexClientId);
    server = TextEditingController(text: a.settings.server);
    diskToken = TextEditingController(text: a.yandexToken);
    folder = TextEditingController(text: a.settings.cloudFolder);
    apiToken = TextEditingController(text: a.importToken);
    autoSync = a.settings.autoSync;
    localAi = a.settings.localAi;
    theme = a.settings.theme;
    accent = a.settings.accent;
    widget.controller.addListener(controllerChanged);
  }

  void controllerChanged() {
    if (!diskTokenEdited && diskToken.text != widget.controller.yandexToken) {
      diskToken.text = widget.controller.yandexToken;
    }
    if (!webDavPasswordEdited &&
        webDavPassword.text != widget.controller.webDavPassword) {
      webDavPassword.text = widget.controller.webDavPassword;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    if (textDebounce?.isActive == true) {
      final pending = snapshot(), controller = widget.controller;
      Future.microtask(
        () => controller.updateSettings(
          pending.$1,
          pending.$2,
          pending.$3,
          webDavSecret: pending.$4,
        ),
      ).catchError((Object _) {});
    }
    textDebounce?.cancel();
    for (final c in [
      server,
      diskToken,
      folder,
      apiToken,
      clientId,
      webDavLogin,
      webDavPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void textChanged(String _) {
    textDebounce?.cancel();
    textDebounce = Timer(const Duration(milliseconds: 450), apply);
  }

  (AppSettings, String, String, String) snapshot() {
    final previous = widget.controller.settings;
    final uri = Uri.tryParse(server.text.trim());
    final validServer =
        server.text.trim().isEmpty ||
        (uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty);
    final validFolder =
        folder.text.startsWith('/') &&
        folder.text.trim() != '/' &&
        !folder.text.contains('..');
    return (
      AppSettings(
        deviceId: previous.deviceId,
        server: validServer ? server.text.trim() : previous.server,
        cloudFolder: validFolder ? folder.text.trim() : previous.cloudFolder,
        theme: theme,
        accent: accent,
        syncMethod: syncMethod,
        yandexLogin: webDavLogin.text.trim(),
        yandexClientId:
            clientId.text.trim().isEmpty ||
                RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(clientId.text.trim())
            ? clientId.text.trim()
            : previous.yandexClientId,
        autoSync: autoSync,
        localAi: localAi,
      ),
      diskTokenEdited ? diskToken.text : widget.controller.yandexToken,
      apiToken.text,
      webDavPasswordEdited
          ? webDavPassword.text
          : widget.controller.webDavPassword,
    );
  }

  Future<bool> apply() async {
    textDebounce?.cancel();
    final pending = snapshot();
    try {
      await widget.controller.updateSettings(
        pending.$1,
        pending.$2,
        pending.$3,
        webDavSecret: pending.$4,
      );
      if (mounted && pending.$2 == diskToken.text) diskTokenEdited = false;
      if (mounted && pending.$4 == webDavPassword.text) {
        webDavPasswordEdited = false;
      }
      if (mounted && saveError.isNotEmpty) setState(() => saveError = '');
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError =
              'Не удалось записать настройки. Проверьте свободное место и повторите изменение.',
        );
      }
      return false;
    }
  }

  Future<void> setupYandex() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Первое подключение Яндекс Диска'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Один раз зарегистрируйте приложение на oauth.yandex.ru, разрешите чтение и запись файлов Диска и добавьте адреса возврата. После регистрации вставьте публичный Client ID в «Настройка подключения». Секретный ключ не нужен.',
            ),
            const SizedBox(height: 16),
            const RecipeText(
              'Android: recipevault://oauth\nWindows: http://localhost:9876/auth',
            ),
            TextButton(
              onPressed: () => Clipboard.setData(
                const ClipboardData(
                  text: 'recipevault://oauth\nhttp://localhost:9876/auth',
                ),
              ),
              child: const Text('Скопировать адреса'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://oauth.yandex.ru/client/new'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Открыть Яндекс OAuth'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
  Future<void> loginYandex() async {
    if (!await apply() || !mounted) return;
    if (widget.controller.settings.yandexClientId.isEmpty) {
      await setupYandex();
      return;
    }
    setState(() => busy = true);
    final auth = YandexAuth();
    try {
      final tokens = await auth.login(
        widget.controller.settings.yandexClientId,
      );
      await widget.controller.connectYandex(tokens);
      diskToken.text = tokens.accessToken;
      if (mounted) message('Яндекс Диск подключён');
      await widget.controller.sync();
    } catch (error) {
      if (mounted) {
        message(
          error is YandexAuthException
              ? error.message
              : error is PlatformException && error.code == 'CANCELED'
              ? 'Вход отменён'
              : 'Вход не завершён. Проверьте интернет и повторите.',
        );
      }
    } finally {
      auth.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    try {
      final bytes = Uint8List.fromList(
        utf8.encode(widget.controller.database.encode()),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить базу рецептов',
        fileName: 'recipes.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (path == null) return;
      // Android writes the bytes through its document provider. Desktop returns a destination.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        message(
          'База экспортирована. Пароли, токены и настройки в файл не входят.',
        );
      }
    } catch (_) {
      if (mounted) message('Не удалось экспортировать базу.');
    }
  }

  Future<void> import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Файл недоступен или превышает 20 МБ');
      }
      final imported = RecipeDatabase.decode(utf8.decode(bytes));
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Объединить базы?'),
          content: Text(
            'В файле ${imported.recipes.length} рецептов. Изменения будут объединены с вашей книгой, конфликтующие правки сохранятся отдельными карточками.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Объединить'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      await widget.controller.merge(imported);
      if (mounted) message('Базы объединены');
    } catch (_) {
      if (mounted) {
        message(
          'Не удалось прочитать базу. Проверьте формат recipes.json. Ваша книга не изменена.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: form,
          child: ListView(
            key: const ValueKey('settings-list'),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Внешний вид',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('appearance-theme'),
                initialValue: theme,
                decoration: const InputDecoration(labelText: 'Тема'),
                items: const [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text('Как на устройстве'),
                  ),
                  DropdownMenuItem(value: 'light', child: Text('Светлая')),
                  DropdownMenuItem(value: 'dark', child: Text('Тёмная')),
                ],
                onChanged: (v) {
                  setState(() => theme = v!);
                  apply();
                },
              ),
              const SizedBox(height: 20),
              const Text('Основной цвет'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Цвета устройства'),
                    selected: accent == 'system',
                    onSelected: (_) {
                      setState(() => accent = 'system');
                      apply();
                    },
                  ),
                  for (final entry in accentColors.entries)
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: entry.value.$2,
                        radius: 9,
                      ),
                      label: Text(entry.value.$1),
                      selected: accent == entry.key,
                      onSelected: (_) {
                        setState(() => accent = entry.key);
                        apply();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                saveError.isEmpty
                    ? 'Настройки применяются автоматически'
                    : saveError,
              ),
              const SizedBox(height: 32),
              Text(
                'Яндекс Диск',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const Text(
                'Укажите один аккаунт и одну папку на обоих устройствах. Рецепты доступны офлайн; при синхронизации изменения объединяются.',
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                key: const ValueKey('sync-method'),
                isExpanded: true,
                initialValue: syncMethod,
                decoration: const InputDecoration(
                  labelText: 'Способ подключения',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'webdav',
                    child: Text(
                      'WebDAV · пароль приложения',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'oauth',
                    child: Text(
                      'OAuth · прежнее подключение',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: busy || widget.controller.syncing
                    ? null
                    : (value) {
                        setState(() => syncMethod = value!);
                        apply();
                      },
              ),
              const SizedBox(height: 12),
              if (syncMethod == 'webdav') ...[
                const Text(
                  'Создайте пароль типа «Файлы WebDAV» в Яндекс ID → Безопасность → Пароли приложений. Регистрация OAuth-приложения не требуется. По условиям Яндекса нужен тариф Яндекс 360 с поддержкой WebDAV.',
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://id.yandex.ru/security/app-passwords'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Создать пароль приложения'),
                ),
                TextFormField(
                  key: const ValueKey('webdav-login'),
                  controller: webDavLogin,
                  enabled: !busy && !widget.controller.syncing,
                  onChanged: textChanged,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Логин Яндекса'),
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (value) =>
                      value != null &&
                          (value.contains(':') ||
                              RegExp(r'[\x00-\x1f]').hasMatch(value))
                      ? 'Введите логин без двоеточия и переноса строки'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('webdav-password'),
                  controller: webDavPassword,
                  enabled: !busy && !widget.controller.syncing,
                  onChanged: (value) {
                    webDavPasswordEdited = true;
                    textChanged(value);
                  },
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Пароль приложения «Файлы WebDAV»',
                    helperText: 'Используйте отдельный пароль приложения',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('webdav-check'),
                  onPressed: busy || widget.controller.syncing
                      ? null
                      : () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          if (!await apply() || !mounted) return;
                          await widget.controller.checkWebDavConnection();
                        },
                  icon: const Icon(Icons.cloud_done_outlined),
                  label: const Text('Проверить подключение'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: busy || widget.controller.syncing
                      ? null
                      : loginYandex,
                  icon: const Icon(Icons.login),
                  label: Text(
                    busy
                        ? 'Ожидаю входа…'
                        : widget.controller.yandexToken.isEmpty
                        ? 'Войти в Яндекс Диск'
                        : 'Войти в другой аккаунт',
                  ),
                ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final controller = widget.controller;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.syncing
                                ? (controller.syncMessage.isEmpty
                                      ? 'Синхронизация…'
                                      : controller.syncMessage)
                                : controller.syncMessage.isNotEmpty
                                ? controller.syncMessage
                                : !controller.cloudConfigured
                                ? 'Яндекс Диск не подключён'
                                : 'Данные подключения сохранены · рецепты доступны офлайн',
                          ),
                          if (controller.lastSynced != null)
                            Text(
                              'Последняя синхронизация: ${controller.lastSynced!.toLocal().hour.toString().padLeft(2, '0')}:${controller.lastSynced!.toLocal().minute.toString().padLeft(2, '0')}',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed:
                                    controller.syncing ||
                                        !controller.cloudConfigured
                                    ? null
                                    : () async {
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        if (await apply()) {
                                          await controller.sync();
                                        }
                                      },
                                icon: const Icon(Icons.sync),
                                label: Text(
                                  controller.syncFailed
                                      ? 'Повторить'
                                      : 'Синхронизировать',
                                ),
                              ),
                              if (controller.cloudConfigured)
                                TextButton(
                                  onPressed: busy || controller.syncing
                                      ? null
                                      : () {
                                          if (syncMethod == 'webdav') {
                                            webDavPassword.clear();
                                            webDavPasswordEdited = true;
                                          } else {
                                            diskToken.clear();
                                            diskTokenEdited = true;
                                          }
                                          apply();
                                        },
                                  child: const Text('Отключить Диск'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (syncMethod == 'oauth')
                ExpansionTile(
                  title: const Text('Настройка подключения'),
                  children: [
                    TextFormField(
                      controller: clientId,
                      onChanged: textChanged,
                      decoration: const InputDecoration(
                        labelText: 'Публичный Client ID Яндекс OAuth',
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (s) =>
                          s == null ||
                              s.trim().isEmpty ||
                              RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(s.trim())
                          ? null
                          : 'Client ID содержит 32 шестнадцатеричных символа',
                    ),
                    TextButton(
                      onPressed: setupYandex,
                      child: const Text('Как зарегистрировать приложение'),
                    ),
                    TextFormField(
                      controller: diskToken,
                      onChanged: (value) {
                        diskTokenEdited = true;
                        textChanged(value);
                      },
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText:
                            'Токен для старого подключения (необязательно)',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: folder,
                enabled: !busy && !widget.controller.syncing,
                onChanged: textChanged,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Папка базы',
                  hintText: '/RecipeVault',
                ),
                validator: (s) =>
                    s != null &&
                        s.startsWith('/') &&
                        s != '/' &&
                        !s.contains('..')
                    ? null
                    : 'Укажите папку, например /RecipeVault',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Автоматическая синхронизация'),
                subtitle: const Text(
                  'После изменений и каждые 3 минуты, пока приложение открыто',
                ),
                value: autoSync,
                onChanged: (v) {
                  setState(() => autoSync = v);
                  apply();
                },
              ),
              const SizedBox(height: 32),
              if (LocalRecipeAi.supported)
                LocalAiSettings(
                  enabled: localAi,
                  onChanged: (value) {
                    setState(() => localAi = value);
                    apply();
                  },
                ),
              Text(
                'Импорт сайтов и YouTube',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const Text(
                'Сайты и текст разбираются на устройстве. Дополнительный сервис можно использовать при выключенном локальном ИИ.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: server,
                onChanged: textChanged,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Адрес сервиса',
                  hintText: 'https://recipes.example.com',
                ),
                validator: (s) {
                  if (s == null || s.trim().isEmpty) return null;
                  final uri = Uri.tryParse(s.trim());
                  return uri != null &&
                          ['https', 'http'].contains(uri.scheme) &&
                          uri.host.isNotEmpty &&
                          uri.userInfo.isEmpty
                      ? null
                      : 'Введите адрес http:// или https://';
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: apiToken,
                onChanged: textChanged,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Ключ сервиса, если задан',
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Перенос и резервная копия',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: export,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Экспортировать recipes.json'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: import,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Импортировать и объединить базу'),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
