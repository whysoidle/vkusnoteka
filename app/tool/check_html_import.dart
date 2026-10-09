import 'dart:convert';
import 'dart:io';
import 'package:recipe_vault/services/html_decoder.dart';
import 'package:recipe_vault/services/website_parser.dart';

/// Diagnose a saved page using exactly the native application's decoder/parser.
void main(List<String> args) {
  if (args.length < 2 || args.length > 3) {
    stderr.writeln(
      'Usage: dart run tool/check_html_import.dart FILE SOURCE_URL [CONTENT_TYPE]',
    );
    exitCode = 2;
    return;
  }
  final text = decodeHtml(
    File(args[0]).readAsBytesSync(),
    contentType: args.length == 3 ? args[2] : '',
  );
  final recipes = parseWebsite(text, args[1]);
  final corrupted = recipes.any(
    (r) => jsonEncode(r.toJson()).contains('\ufffd'),
  );
  stdout.writeln(
    jsonEncode({
      'recipes': recipes.length,
      'replacementCharacters': corrupted,
      'results': recipes
          .map(
            (r) => {
              'title': r.title,
              'ingredients': r.ingredients.length,
              'steps': r.steps.length,
              'draft': r.draft,
            },
          )
          .toList(),
    }),
  );
  if (corrupted) {
    exitCode = 1;
  }
}
