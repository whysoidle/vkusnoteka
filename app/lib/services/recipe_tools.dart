import '../models/recipe.dart';

export 'ingredient_scaling.dart' show scaleIngredient;

String normalizeWords(String text) => text
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();
String canonicalRecipeUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return '';
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  String? video;
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    video = uri.pathSegments.first;
  }
  if (host == 'youtube.com' || host == 'm.youtube.com') {
    video = uri.queryParameters['v'];
    if (video == null &&
        uri.pathSegments.length >= 2 &&
        ['shorts', 'live', 'embed'].contains(uri.pathSegments.first)) {
      video = uri.pathSegments[1];
    }
  }
  if (video != null && RegExp(r'^[\w-]{11}$').hasMatch(video)) {
    return 'youtube:$video';
  }
  final params = <String, String>{};
  final keys =
      uri.queryParameters.keys
          .where(
            (key) =>
                !key.startsWith('utm_') &&
                !['fbclid', 'gclid', 'yclid'].contains(key),
          )
          .toList()
        ..sort();
  for (final key in keys) {
    params[key] = uri.queryParameters[key]!;
  }
  return Uri(
    scheme: 'https',
    host: host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

Set<String> ingredientWords(Recipe r) => r.ingredients
    .map((s) => normalizeWords(s.split(RegExp(r'\s*[—–:]\s*')).first))
    .where((s) => s.isNotEmpty)
    .toSet();
List<Recipe> duplicateRecipes(Recipe incoming, List<Recipe> catalog) {
  final url = canonicalRecipeUrl(incoming.sourceUrl);
  final title = normalizeWords(incoming.title),
      products = ingredientWords(incoming);
  return catalog.where((r) {
    if (r.id == incoming.id) return false;
    if (url.isNotEmpty && url == canonicalRecipeUrl(r.sourceUrl)) return true;
    final otherTitle = normalizeWords(r.title);
    if (title.isEmpty ||
        title == 'новый рецепт' ||
        title == 'рецепт по ссылке') {
      return false;
    }
    if (title == otherTitle) return true;
    final a = title.split(' ').toSet(), b = otherTitle.split(' ').toSet();
    final names = a.intersection(b).length / a.union(b).length;
    final otherProducts = ingredientWords(r);
    if (products.isEmpty || otherProducts.isEmpty) return false;
    final foods =
        products.intersection(otherProducts).length /
        products.union(otherProducts).length;
    return names >= .7 && foods >= .6;
  }).toList();
}

Recipe mergeImportedRecipe(Recipe old, Recipe incoming) => Recipe.fromJson({
  ...old.toJson(),
  ...incoming.toJson(),
  'id': old.id,
  'favorite': old.favorite,
  'title': ['Новый рецепт', 'Рецепт по ссылке'].contains(incoming.title)
      ? old.title
      : incoming.title,
  'time': incoming.time.isEmpty ? old.time : incoming.time,
  'servings': incoming.servings.isEmpty ? old.servings : incoming.servings,
  'photo': incoming.photo.isEmpty ? old.photo : incoming.photo,
  'tags': {...old.tags, ...incoming.tags}.toList(),
  'collections': {...old.collections, ...incoming.collections}.toList(),
  'category': incoming.category == 'Без категории'
      ? old.category
      : incoming.category,
  'ingredients': incoming.ingredients.isEmpty
      ? old.ingredients
      : incoming.ingredients,
  'steps': incoming.steps.isEmpty ? old.steps : incoming.steps,
  'notes': [
    old.notes,
    if (incoming.notes != old.notes) incoming.notes,
  ].where((s) => s.isNotEmpty).join('\n\n'),
  'sourceUrl': incoming.sourceUrl.isEmpty ? old.sourceUrl : incoming.sourceUrl,
  'sourceText': incoming.sourceText.isEmpty
      ? old.sourceText
      : incoming.sourceText,
});

double? parseServings(String value) {
  final match = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*(?:порц|чел|person|serving|$)',
    caseSensitive: false,
  ).firstMatch(value);
  final n = match == null
      ? null
      : double.tryParse(match[1]!.replaceAll(',', '.'));
  return n != null && n > 0 ? n : null;
}

String formatQuantity(double value) => value
    .toStringAsFixed(2)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

int? recipeMinutes(String text) {
  final normalized = text.toLowerCase();
  int total = 0;
  final hours = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:ч(?:ас)?|hour|hr)',
  ).firstMatch(normalized);
  final minutes = RegExp(r'(\d+)\s*(?:мин|minute|min)').firstMatch(normalized);
  if (hours != null) {
    total += (double.parse(hours[1]!.replaceAll(',', '.')) * 60).round();
  }
  if (minutes != null) total += int.parse(minutes[1]!);
  if (hours == null && minutes == null) return null;
  return total;
}

List<Duration> stepDurations(String step) {
  final source = step.replaceAll(RegExp(r'\[\d+:\d+\]'), '');
  final results = <Duration>[];
  for (final match in RegExp(
    r'(\d+)\s*(?:[–-]\s*(\d+)\s*)?(мин\w*|час\w*|сек\w*)',
    caseSensitive: false,
  ).allMatches(source)) {
    final n = int.parse(match[2] ?? match[1]!);
    final unit = match[3]!.toLowerCase();
    results.add(
      Duration(
        seconds:
            n *
            (unit.startsWith('час')
                ? 3600
                : unit.startsWith('мин')
                ? 60
                : 1),
      ),
    );
  }
  return results.where((d) => d.inSeconds > 0 && d.inHours <= 24).toList();
}
