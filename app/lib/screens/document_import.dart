import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../widgets/page_list.dart';
import 'package:image_picker/image_picker.dart';
import '../services/document_import.dart';
import '../services/import_job.dart';

class DocumentImportScreen extends StatefulWidget {
  const DocumentImportScreen({super.key});
  @override
  State<DocumentImportScreen> createState() => _DocumentImportScreenState();
}

class _DocumentImportScreenState extends State<DocumentImportScreen> {
  final text = TextEditingController(),
      source = TextEditingController(),
      first = TextEditingController(text: '1'),
      last = TextEditingController(text: '20');
  String path = '', name = '', status = '';
  List<String> warnings = [];
  bool busy = false;
  ImportJob? work;
  final importer = DocumentImporter();
  @override
  void dispose() {
    work?.cancel();
    for (final c in [text, source, first, last]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choose({bool camera = false}) async {
    try {
      String? selected;
      if (camera) {
        selected = (await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 2400,
          maxHeight: 2400,
        ))?.path;
      } else {
        selected = (await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'bmp'],
        ))?.files.single.path;
      }
      if (selected == null || !mounted) return;
      setState(() {
        path = selected!;
        name = path.split(RegExp(r'[/\\]')).last;
        text.clear();
        warnings = [];
        status = '';
      });
      await recognize();
    } catch (_) {
      if (mounted) {
        setState(
          () => status =
              'Не удалось открыть файл. Попробуйте выбрать его ещё раз.',
        );
      }
    }
  }

  Future<void> recognize() async {
    final job = ImportJob();
    work = job;
    setState(() {
      busy = true;
      status = 'Подготавливаю документ…';
    });
    try {
      final result = await importer.read(
        path,
        job: job,
        firstPage: int.tryParse(first.text) ?? 0,
        lastPage: int.tryParse(last.text) ?? 0,
        onProgress: (value) {
          if (mounted) setState(() => status = value);
        },
      );
      if (!mounted) return;
      setState(() {
        text.text = result.text;
        warnings = result.warnings;
        status = result.text.isEmpty
            ? 'Текст не найден. Можно заполнить поле вручную.'
            : 'Проверьте текст, затем нажмите «Разобрать рецепт».';
      });
    } on ImportCancelled {
      if (mounted) setState(() => status = 'Распознавание отменено');
    } catch (error) {
      if (mounted) {
        setState(
          () => status = error is FormatException
              ? error.message
              : 'Не удалось распознать документ. Можно заполнить текст вручную.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
      work = null;
    }
  }

  void submit() {
    final url = source.text.trim(), uri = Uri.tryParse(source.text.trim());
    if (url.isNotEmpty &&
        (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty)) {
      setState(() => status = 'Укажите ссылку http:// или https://');
      return;
    }
    if (text.text.trim().isEmpty || text.text.length > 50000) {
      setState(() => status = 'Введите текст до 50 000 символов');
      return;
    }
    Navigator.pop(
      context,
      DocumentText(text.text.trim(), name, sourceUrl: url, warnings: warnings),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Импорт документа')),
    body: PageList(
      maxWidth: 820,
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Скриншот, фотография или PDF. Распознанный текст можно исправить перед разбором рецепта.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : choose,
              icon: const Icon(Icons.attach_file),
              label: const Text('Выбрать файл'),
            ),
            if (Platform.isAndroid)
              OutlinedButton.icon(
                onPressed: busy ? null : () => choose(camera: true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Сфотографировать'),
              ),
          ],
        ),
        if (name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(name),
          ),
        if (path.toLowerCase().endsWith('.pdf')) ...[
          const Text('Диапазон PDF, до 20 страниц за один импорт'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: first,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'С первой страницы',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: last,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'По страницу'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: busy ? null : recognize,
            child: const Text('Распознать выбранные страницы'),
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          TextButton(
            onPressed: () {
              work?.cancel();
              setState(() => status = 'Останавливаю распознавание…');
            },
            child: const Text('Отмена'),
          ),
        ],
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(status),
          ),
        for (final warning in warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(warning),
          ),
        TextField(
          controller: text,
          minLines: 8,
          maxLines: null,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          decoration: const InputDecoration(labelText: 'Распознанный текст'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: source,
          decoration: const InputDecoration(
            labelText: 'Ссылка на источник (необязательно)',
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: busy ? null : submit,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Разобрать рецепт'),
        ),
      ],
    ),
  );
}
