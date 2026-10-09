import 'dart:io';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:image/image.dart' as img;
import 'package:recipe_vault/services/text_parser.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: check_pdf.dart INPUT.pdf PAGE.png');
    exitCode = 2;
    return;
  }
  await pdfrxInitialize(
    tmpPath: '${Directory.systemTemp.path}/recipe-pdf-probe',
  );
  final document = await PdfDocument.openFile(args.first);
  try {
    final text = (await document.pages.first.loadText())?.fullText ?? '';
    final recipe = parseText(text);
    if (recipe.ingredients.length != 3 ||
        recipe.steps.length != 2 ||
        !text.contains('Творог') ||
        text.contains('�')) {
      throw StateError('Russian recipe text was not preserved');
    }
    final page = document.pages.first;
    final scale = 2200 / page.height;
    final image = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
    );
    if (image == null) throw StateError('Page render failed');
    try {
      await File(args.last).writeAsBytes(img.encodePng(image.createImageNF()));
    } finally {
      image.dispose();
    }
    stdout.writeln(
      'PDF verified: ${recipe.title}, ${recipe.ingredients.length} ingredients, ${recipe.steps.length} steps; page rendered for OCR.',
    );
  } finally {
    await document.dispose();
  }
}
