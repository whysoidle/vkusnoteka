import 'dart:convert';
import 'dart:io';
import 'package:recipe_vault/services/import_job.dart';
import 'package:recipe_vault/services/youtube_subtitles.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_youtube_subtitles.dart YOUTUBE_URL',
    );
    exitCode = 2;
    return;
  }
  final result = await YouTubeSubtitles().load(args.single, ImportJob());
  stdout.writeln(
    jsonEncode({
      'title': result.title,
      'descriptionCharacters': result.description.length,
      'subtitleCharacters': result.transcript.length,
      'warnings': result.warnings,
    }),
  );
  if (result.transcript.isEmpty) exitCode = 1;
}
