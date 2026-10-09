import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/import_job.dart';
import '../services/local_model_store.dart';
import '../services/local_recipe_ai.dart';

class LocalAiSettings extends StatefulWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const LocalAiSettings({
    super.key,
    required this.enabled,
    required this.onChanged,
  });
  @override
  State<LocalAiSettings> createState() => _LocalAiSettingsState();
}

class _LocalAiSettingsState extends State<LocalAiSettings> {
  LocalModelStore? store;
  ImportJob? job;
  bool ready = false, busy = false;
  int received = 0;
  String message = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (!await LocalRecipeAi.deviceSupported) {
        if (mounted) {
          setState(
            () => message =
                'Локальный ИИ доступен на Android 8+ с ARM64 и на macOS 12+. На этом устройстве доступен обычный импорт.',
          );
        }
        return;
      }
      final model = await LocalModelStore.open();
      final installed = await model.ready;
      if (mounted) {
        setState(() {
          store = model;
          ready = installed;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Не удалось открыть хранилище модели.');
      }
    }
  }

  @override
  void dispose() {
    job?.cancel();
    super.dispose();
  }

  Future<void> download() async {
    final model = store;
    if (model == null || busy) return;
    final work = ImportJob();
    job = work;
    setState(() {
      busy = true;
      received = 0;
      message = '';
    });
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await model.download(
        job: work,
        onProgress: (bytes, total) {
          final now = DateTime.now();
          if (mounted &&
              (bytes == total ||
                  now.difference(lastUpdate).inMilliseconds > 250)) {
            lastUpdate = now;
            setState(() => received = bytes);
          }
        },
      );
      if (mounted) {
        setState(() {
          ready = true;
          message = 'Модель готова. Можно отправить ссылку YouTube в чат.';
        });
      }
    } on ImportCancelled {
      if (mounted) {
        setState(
          () => message =
              'Загрузка остановлена. Следующее скачивание продолжится с сохранённой части.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is ModelDownloadException
              ? e.message
              : 'Загрузка не завершена. Проверьте интернет и свободное место, затем повторите.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          job = null;
        });
      }
    }
  }

  Future<void> remove() async {
    if (busy || store == null) return;
    setState(() => busy = true);
    try {
      await store!.remove();
      if (mounted) {
        setState(() {
          ready = false;
          message = 'Модель удалена. Сохранённые рецепты доступны.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Не удалось удалить модель.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Локальный ИИ', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 10),
      const Text(
        'Разбирает субтитры YouTube и свободный текст на устройстве. Интернет нужен для получения субтитров и первоначального скачивания модели.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Использовать локальный ИИ'),
        subtitle: const Text(
          'Без отдельного сервера; карточку можно проверить и исправить',
        ),
        value: widget.enabled,
        onChanged: widget.onChanged,
      ),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocalModelStore.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                ready
                    ? 'Установлена · 977 МБ'
                    : 'Загрузка 977 МБ · рекомендуется Wi-Fi и 1,5 ГБ свободного места',
              ),
              if (busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: received == LocalModelStore.size
                      ? null
                      : received / LocalModelStore.size,
                ),
                const SizedBox(height: 8),
                Text(
                  received == LocalModelStore.size
                      ? 'Проверяю целостность модели…'
                      : '${(received / 1000000).round()} / ${(LocalModelStore.size / 1000000).round()} МБ',
                ),
                TextButton(
                  onPressed: job?.cancelled == true || job == null
                      ? null
                      : () {
                          job?.cancel();
                          setState(() {});
                        },
                  child: const Text('Остановить загрузку'),
                ),
              ] else ...[
                const SizedBox(height: 14),
                if (ready)
                  OutlinedButton.icon(
                    onPressed: remove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить модель'),
                  )
                else
                  FilledButton.icon(
                    onPressed: store == null ? null : download,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Скачать модель'),
                  ),
              ],
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(message),
              ],
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://huggingface.co/litert-community/Qwen3-1.7B',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('О модели и лицензии'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 32),
    ],
  );
}
