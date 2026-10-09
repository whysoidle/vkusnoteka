import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';
import 'import_job.dart';
import 'photos.dart';

class DocumentText {
  final String text, name, sourceUrl;
  final List<String> warnings;
  const DocumentText(
    this.text,
    this.name, {
    this.sourceUrl = '',
    this.warnings = const [],
  });
}

class DocumentImporter {
  static const channel = MethodChannel('recipe_vault/documents');
  Future<String> ocr(String imagePath, ImportJob job) async {
    job.check();
    final image = await prepareOcrImage(imagePath);
    try {
      job.check();
      String result;
      if (Platform.isAndroid || Platform.isMacOS) {
        result =
            await channel.invokeMethod<String>('ocr', {'path': image.path}) ??
            '';
      } else if (Platform.isWindows) {
        final temp = await getTemporaryDirectory();
        final script = File('${temp.path}/recipe-windows-ocr.ps1');
        await script.writeAsString(
          await rootBundle.loadString('assets/windows_ocr.ps1'),
          encoding: utf8,
        );
        final process = await Process.start('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-ImagePath',
          image.path,
        ]);
        final unregister = job.onCancel(process.kill);
        try {
          final output = process.stdout.transform(utf8.decoder).join();
          final errors = process.stderr.transform(utf8.decoder).join();
          final completed =
              await Future.wait<Object>([
                process.exitCode,
                output,
                errors,
              ]).timeout(
                const Duration(seconds: 60),
                onTimeout: () {
                  process.kill();
                  throw const FormatException(
                    'Распознавание заняло слишком много времени. Выберите меньший фрагмент.',
                  );
                },
              );
          final status = completed[0] as int;
          result = completed[1] as String;
          final error = completed[2] as String;
          if (status != 0) {
            throw FormatException(
              error.trim().isEmpty
                  ? 'Не удалось распознать изображение'
                  : error.trim(),
            );
          }
        } finally {
          unregister();
          process.kill();
        }
      } else {
        throw const FormatException(
          'Распознавание изображений доступно на Android, Windows и macOS',
        );
      }
      job.check();
      if (result.length > 50000) {
        throw const FormatException(
          'Распознанный текст превышает 50 000 символов. Выберите меньший фрагмент.',
        );
      }
      return result.trim();
    } finally {
      if (await image.exists()) await image.delete();
    }
  }

  Future<DocumentText> read(
    String path, {
    required ImportJob job,
    int firstPage = 1,
    int lastPage = 20,
    void Function(String)? onProgress,
  }) async {
    final file = File(path), name = path.split(RegExp(r'[/\\]')).last;
    if (await file.length() > 50 * 1024 * 1024) {
      throw const FormatException('Файл превышает 50 МБ');
    }
    job.check();
    if (!path.toLowerCase().endsWith('.pdf')) {
      onProgress?.call('Распознаю русский и английский текст…');
      final text = await ocr(path, job);
      return DocumentText(
        text,
        name,
        warnings: const [
          'Текст распознан с изображения. Проверьте названия, дроби и количества.',
        ],
      );
    }
    if (firstPage < 1 || lastPage < firstPage || lastPage - firstPage >= 20) {
      throw const FormatException(
        'Выберите не более 20 страниц PDF за один импорт',
      );
    }
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(path);
    final warnings = <String>[];
    try {
      if (firstPage > document.pages.length) {
        throw FormatException('В PDF только ${document.pages.length} страниц');
      }
      final end = lastPage.clamp(firstPage, document.pages.length);
      if (firstPage > 1 || end < document.pages.length) {
        warnings.add(
          'Выбраны страницы $firstPage–$end из ${document.pages.length}. Остальные страницы не импортировались.',
        );
      }
      final texts = <String>[];
      var usedOcr = false;
      for (var i = firstPage; i <= end; i++) {
        job.check();
        onProgress?.call('Читаю страницу $i из $end…');
        final page = document.pages[i - 1];
        var text = (await page.loadText())?.fullText.trim() ?? '';
        if (text.length < 20 || text.contains('�')) {
          onProgress?.call('Распознаю страницу $i…');
          final scale =
              2200 / (page.width > page.height ? page.width : page.height);
          final image = await page.render(
            fullWidth: page.width * scale,
            fullHeight: page.height * scale,
          );
          if (image == null) {
            throw FormatException('Не удалось прочитать страницу $i');
          }
          File? png;
          try {
            final temp = await getTemporaryDirectory();
            png = File('${temp.path}/recipe-pdf-${const Uuid().v4()}.png');
            final bitmap = await image.createImage();
            try {
              final bytes = await bitmap.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (bytes == null) {
                throw const FormatException('Не удалось прочитать страницу');
              }
              await png.writeAsBytes(bytes.buffer.asUint8List());
            } finally {
              bitmap.dispose();
            }
            text = await ocr(png.path, job);
          } finally {
            image.dispose();
            if (png != null && await png.exists()) await png.delete();
          }
          usedOcr = true;
        }
        texts.add(text);
        if (texts.join('\n\n').length > 50000) {
          throw const FormatException(
            'Текст превышает 50 000 символов. Уменьшите диапазон страниц.',
          );
        }
      }
      if (usedOcr) {
        warnings.add(
          'Часть PDF распознана со сканов. Проверьте названия и количества.',
        );
      }
      job.check();
      return DocumentText(texts.join('\n\n'), name, warnings: warnings);
    } finally {
      await document.dispose();
    }
  }
}
