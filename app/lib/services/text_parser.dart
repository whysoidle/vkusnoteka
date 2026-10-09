import '../models/recipe.dart';

Recipe parseText(String text, {String sourceUrl = '', String title = ''}) {
  final lines = text
      .split('\n')
      .map((s) => s.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final ingredients = <String>[], steps = <String>[], notes = <String>[];
  var section = '', servings = '', time = '';
  final ingredientHeader = RegExp(
    r'^(ингредиенты|состав|продукты|ingredients)\s*[:：]?$',
    caseSensitive: false,
  );
  final stepsHeader = RegExp(
    r'^(приготовление|способ приготовления|шаги|инструкция|instructions|directions|method)\s*[:：]?$',
    caseSensitive: false,
  );
  final quantity = RegExp(
    r'\d[\d.,/\s]*\s*(кг|гр?\.?|мл|л|шт\.?|ст\.?\s*л\.?|ч\.?\s*л\.?|стакан\S*|зубчик\S*|tbsp|tsp|cups?|grams?|kg|ml)(\s|$|[.,])',
    caseSensitive: false,
  );
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (ingredientHeader.hasMatch(line)) {
      section = 'ingredients';
    } else if (stepsHeader.hasMatch(line)) {
      section = 'steps';
    } else if (RegExp(
      r'^(заметки|советы|примечания|notes)\s*:',
      caseSensitive: false,
    ).hasMatch(line)) {
      section = 'notes';
      notes.add(line.substring(line.indexOf(':') + 1).trim());
    } else if (RegExp(
      r'^(порци[ияй]|servings)\s*:',
      caseSensitive: false,
    ).hasMatch(line)) {
      servings = line.substring(line.indexOf(':') + 1).trim();
    } else if (RegExp(
      r'^(время|time)\s*:',
      caseSensitive: false,
    ).hasMatch(line)) {
      time = line.substring(line.indexOf(':') + 1).trim();
    } else if (i == 0 && title.isEmpty) {
      continue;
    } else if (section == 'ingredients') {
      ingredients.add(line);
    } else if (section == 'steps' || RegExp(r'^\d+[.)]\s').hasMatch(line)) {
      steps.add(line.replaceFirst(RegExp(r'^\d+[.)]\s*'), ''));
    } else if (line.length < 160 && quantity.hasMatch(line)) {
      ingredients.add(line);
    } else {
      notes.add(line);
    }
  }
  return Recipe(
    id: Recipe.blank().id,
    title: title.isNotEmpty
        ? title
        : lines.isEmpty
        ? 'Новый рецепт'
        : lines.first,
    sourceUrl: sourceUrl,
    sourceText: text,
    ingredients: ingredients,
    steps: steps,
    notes: notes.join('\n'),
    servings: servings,
    time: time,
    draft: ingredients.isEmpty || steps.isEmpty,
  );
}
