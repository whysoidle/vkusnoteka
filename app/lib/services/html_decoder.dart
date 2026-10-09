import 'dart:convert';
import 'package:charset/charset.dart';
import 'package:html/parser.dart' as html;

String? _charset(String value) => RegExp(
  r'''charset\s*=\s*["']?([a-zA-Z0-9._:-]+)''',
  caseSensitive: false,
).firstMatch(value)?.group(1);

Encoding? _codec(String? label) {
  if (label == null) return null;
  final name = label.trim().toLowerCase();
  return Charset.getByName(switch (name) {
    'cp1251' || 'windows1251' || 'x-cp1251' => 'windows-1251',
    'utf8' => 'utf-8',
    _ => name,
  });
}

/// Decode the original bytes before parsing. Once bytes have been replaced by
/// U+FFFD, the original Cyrillic letters cannot be recovered from that string.
String decodeHtml(List<int> bytes, {String contentType = ''}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return utf8.decode(bytes);
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    return utf16.decode(bytes);
  }
  var codec = _codec(_charset(contentType));
  if (codec == null) {
    // Latin-1 keeps all byte values intact while reading ASCII-only declarations.
    final head = html.parse(latin1.decode(bytes.take(8192).toList()));
    for (final meta in head.querySelectorAll('meta')) {
      final label =
          meta.attributes['charset'] ??
          (meta.attributes['http-equiv']?.toLowerCase() == 'content-type'
              ? _charset(meta.attributes['content'] ?? '')
              : null);
      codec = _codec(label);
      if (codec != null) break;
    }
  }
  // Strict UTF-8 prevents silently persisting replacement glyphs in the catalog.
  return (codec ?? utf8).decode(bytes);
}
