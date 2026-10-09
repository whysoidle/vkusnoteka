import 'dart:convert';
import 'package:html/parser.dart' as html;
import '../models/recipe.dart';
import 'text_parser.dart';

String clean(dynamic text) =>
    html.parseFragment(text?.toString() ?? '').text?.trim() ?? '';
String readableTime(dynamic value) {
  final text = clean(value);
  final match = RegExp(
    r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
  ).firstMatch(text);
  if (match == null) return text;
  return [
    if (match[1] != null) '${match[1]} ч',
    if (match[2] != null) '${match[2]} мин',
    if (match[3] != null) '${match[3]} сек',
  ].join(' ');
}

List<Map<String, dynamic>> findRecipes(dynamic value) {
  final found = <Map<String, dynamic>>[];
  if (value is List) {
    for (final item in value) {
      found.addAll(findRecipes(item));
    }
  } else if (value is Map<String, dynamic>) {
    final type = value['@type'];
    final types = type is List ? type : [type];
    if (types.any((t) => t.toString().split('/').last == 'Recipe')) {
      found.add(value);
    }
    for (final child in value.values) {
      if (child is Map || child is List) found.addAll(findRecipes(child));
    }
  }
  return found;
}

List<String> extractSteps(dynamic value) {
  if (value is List) return value.expand(extractSteps).toList();
  if (value is Map) {
    return extractSteps(value['itemListElement'] ?? value['text'] ?? '');
  }
  if (value is String) {
    final fragment = html.parseFragment(value);
    final blocks = fragment.querySelectorAll('p, li');
    return (blocks.isNotEmpty ? blocks.map((e) => e.text) : value.split('\n'))
        .map(clean)
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return [];
}

String ingredient(dynamic value) => value is Map
    ? [
        'name',
        'value',
        'unitText',
        'unitCode',
      ].where((k) => value[k] != null).map((k) => clean(value[k])).join(' ')
    : clean(value);

bool isYouTube(String url) {
  final host = Uri.parse(url).host.toLowerCase();
  return [
    'youtu.be',
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
  ].contains(host);
}

List<Recipe> parseWebsite(String page, String url) {
  final document = html.parse(page);
  final title =
      document.querySelector('title')?.text.trim() ?? 'Рецепт с сайта';
  if (isYouTube(url)) {
    final descriptionMatch = RegExp(
      r'"shortDescription"\s*:\s*("(?:[^"\\]|\\.)*")',
    ).firstMatch(page);
    final titleMatch = RegExp(
      r'"videoDetails"\s*:\s*\{.*?"title"\s*:\s*("(?:[^"\\]|\\.)*")',
      dotAll: true,
    ).firstMatch(page);
    final description = descriptionMatch == null
        ? ''
        : jsonDecode(descriptionMatch[1]!) as String;
    final videoTitle = titleMatch == null
        ? title
        : jsonDecode(titleMatch[1]!) as String;
    if (description.trim().isEmpty) {
      return [Recipe.blank(url: url, title: videoTitle)];
    }
    final recipe = parseText(description, sourceUrl: url, title: videoTitle);
    return [recipe];
  }
  final found = <Recipe>[];
  for (final script in document.querySelectorAll(
    'script[type="application/ld+json"]',
  )) {
    dynamic data;
    try {
      data = jsonDecode(script.text);
    } catch (_) {
      continue;
    }
    for (final node in findRecipes(data)) {
      final raw = node['recipeIngredient'] ?? [];
      final ingredients = (raw is List ? raw : [raw])
          .map(ingredient)
          .where((s) => s.isNotEmpty)
          .toList();
      final steps = extractSteps(node['recipeInstructions']);
      final category = node['recipeCategory'];
      final servings = node['recipeYield'];
      found.add(
        Recipe(
          id: Recipe.blank().id,
          title: clean(node['name']).isEmpty ? title : clean(node['name']),
          ingredients: ingredients,
          steps: steps,
          sourceUrl: url,
          category: category == null
              ? 'Без категории'
              : clean(category is List ? category.firstOrNull : category),
          servings: clean(servings is List ? servings.join(', ') : servings),
          time: readableTime(node['totalTime'] ?? node['cookTime']),
          notes: clean(node['description']),
          draft: ingredients.isEmpty || steps.isEmpty,
        ),
      );
    }
  }
  if (found.isNotEmpty) return found;
  final host = Uri.parse(url).host.toLowerCase();
  if (host == 'russianfood.com' || host.endsWith('.russianfood.com')) {
    final recipeTitle = document.querySelector('h1.title')?.text.trim();
    final ingredients = document
        .querySelectorAll('table.ingr tr[class^="ingr_tr_"] td')
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty && s != '*')
        .toList();
    final steps = document
        .querySelectorAll('.step_images_n .step_n > p')
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (recipeTitle != null &&
        recipeTitle.isNotEmpty &&
        (ingredients.isNotEmpty || steps.isNotEmpty)) {
      return [
        Recipe(
          id: Recipe.blank().id,
          title: recipeTitle,
          ingredients: ingredients,
          steps: steps,
          sourceUrl: url,
          servings:
              document
                  .querySelector('table.ingr .portion')
                  ?.text
                  .trim()
                  .replaceAll(RegExp(r'^\(|\)$'), '') ??
              '',
          draft: ingredients.isEmpty || steps.isEmpty,
        ),
      ];
    }
  }
  for (final element in document.querySelectorAll(
    'script, style, nav, header, footer',
  )) {
    element.remove();
  }
  final body =
      document.querySelector('article') ??
      document.querySelector('main') ??
      document.body;
  // Preserve line boundaries of actual paragraphs and ingredient list items.
  final nodes = body?.querySelectorAll('h1, h2, h3, p, li') ?? [];
  final text = nodes.isEmpty
      ? body?.text ?? ''
      : nodes.map((e) => e.text.trim()).where((s) => s.isNotEmpty).join('\n');
  return [
    parseText(
      text.length > 50000 ? text.substring(0, 50000) : text,
      sourceUrl: url,
      title: title,
    ),
  ];
}
