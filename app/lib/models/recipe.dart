import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

const categories = [
  'Без категории',
  'Завтраки',
  'Супы',
  'Основные блюда',
  'Салаты',
  'Выпечка',
  'Десерты',
  'Напитки',
];

class Recipe {
  final String id,
      title,
      category,
      servings,
      time,
      notes,
      sourceUrl,
      sourceText,
      photo;
  final List<String> ingredients, steps, tags, collections;
  final bool favorite, draft;

  const Recipe({
    required this.id,
    required this.title,
    this.category = 'Без категории',
    this.servings = '',
    this.time = '',
    this.notes = '',
    this.sourceUrl = '',
    this.sourceText = '',
    this.photo = '',
    this.tags = const [],
    this.collections = const [],
    this.ingredients = const [],
    this.steps = const [],
    this.favorite = false,
    this.draft = true,
  });

  factory Recipe.blank({String url = '', String title = 'Новый рецепт'}) =>
      Recipe(id: const Uuid().v4(), title: title, sourceUrl: url);

  factory Recipe.fromJson(Map<String, dynamic> j, {String? id}) {
    List<String> list(String key) => (j[key] as List? ?? []).cast<String>();
    return Recipe(
      id: id ?? j['id'] as String? ?? const Uuid().v4(),
      title: j['title'] as String? ?? 'Новый рецепт',
      category: j['category'] as String? ?? 'Без категории',
      servings: j['servings'] as String? ?? '',
      time: j['time'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      sourceUrl: j['sourceUrl'] as String? ?? '',
      sourceText: j['sourceText'] as String? ?? '',
      photo: j['photo'] as String? ?? '',
      tags: list('tags'),
      collections: list('collections'),
      ingredients: list('ingredients'),
      steps: list('steps'),
      favorite: j['favorite'] as bool? ?? false,
      draft: j['draft'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'servings': servings,
    'time': time,
    'notes': notes,
    'sourceUrl': sourceUrl,
    'sourceText': sourceText,
    'photo': photo,
    'tags': tags,
    'collections': collections,
    'ingredients': ingredients,
    'steps': steps,
    'favorite': favorite,
    'draft': draft,
  };

  Recipe copyWith({String? id, String? title, bool? favorite}) =>
      Recipe.fromJson({
        ...toJson(),
        'id': ?id,
        'title': ?title,
        'favorite': ?favorite,
      });
}

String canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(canonical).join(',')}]';
  return jsonEncode(value);
}

class Record {
  final String id, modifiedAt;
  final Map<String, int> clock;
  final Recipe? recipe;
  bool get deleted => recipe == null;
  const Record({
    required this.id,
    required this.modifiedAt,
    required this.clock,
    this.recipe,
  });
  factory Record.fromJson(Map<String, dynamic> j) {
    final clock = Map<String, int>.from(j['clock'] as Map);
    if (clock.isEmpty || clock.values.any((v) => v <= 0)) {
      throw const FormatException('Некорректные версии рецепта');
    }
    final id = j['id'] as String;
    DateTime.parse(j['modifiedAt'] as String);
    return Record(
      id: id,
      modifiedAt: j['modifiedAt'] as String,
      clock: clock,
      recipe: j['deleted'] == true
          ? null
          : Recipe.fromJson(
              Map<String, dynamic>.from(j['recipe'] as Map),
              id: id,
            ),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'modifiedAt': modifiedAt,
    'clock': {for (final key in (clock.keys.toList()..sort())) key: clock[key]},
    'deleted': deleted,
    'recipe': recipe?.toJson(),
  };
  String get digest =>
      sha256.convert(utf8.encode(canonical(recipe?.toJson()))).toString();
}

class RecipeDatabase {
  final Map<String, Record> records;
  RecipeDatabase([Map<String, Record>? records])
    : records = Map.of(records ?? {});
  factory RecipeDatabase.decode(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1 || json['records'] is! List) {
      throw const FormatException(
        'Неподдерживаемый формат базы. Исходный файл не изменён.',
      );
    }
    final records = <String, Record>{};
    for (final item in json['records'] as List) {
      final record = Record.fromJson(Map<String, dynamic>.from(item as Map));
      if (records.containsKey(record.id)) {
        throw const FormatException('Повторяющийся ID в базе');
      }
      records[record.id] = record;
    }
    return RecipeDatabase(records);
  }
  String encode() {
    final ids = records.keys.toList()..sort();
    return const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'records': ids.map((id) => records[id]!.toJson()).toList(),
    });
  }

  List<Recipe> get recipes =>
      records.values.where((r) => !r.deleted).map((r) => r.recipe!).toList()
        ..sort(
          (a, b) =>
              records[b.id]!.modifiedAt.compareTo(records[a.id]!.modifiedAt),
        );

  void put(Recipe recipe, String device) => _write(recipe.id, recipe, device);
  void remove(String id, String device) => _write(id, null, device);
  void _write(String id, Recipe? recipe, String device) {
    final clock = Map<String, int>.of(records[id]?.clock ?? {});
    clock[device] = (clock[device] ?? 0) + 1;
    records[id] = Record(
      id: id,
      modifiedAt: DateTime.now().toUtc().toIso8601String(),
      clock: clock,
      recipe: recipe,
    );
  }
}

bool dominates(Map<String, int> a, Map<String, int> b) =>
    {...a.keys, ...b.keys}.every((k) => (a[k] ?? 0) >= (b[k] ?? 0));

Map<String, int> unionClock(Map<String, int> a, Map<String, int> b) => {
  for (final k in {...a.keys, ...b.keys})
    k: (a[k] ?? 0) > (b[k] ?? 0) ? a[k]! : b[k] ?? 0,
};

/// Concurrent edits preserve both recipes; ordinary later edits supersede earlier ones.
RecipeDatabase mergeDatabases(RecipeDatabase a, RecipeDatabase b) {
  final merged = RecipeDatabase(a.records);
  for (final incoming in b.records.values) {
    final local = merged.records[incoming.id];
    if (local == null) {
      merged.records[incoming.id] = incoming;
      continue;
    }
    if (dominates(local.clock, incoming.clock) &&
        !dominates(incoming.clock, local.clock)) {
      continue;
    }
    if (dominates(incoming.clock, local.clock) &&
        !dominates(local.clock, incoming.clock)) {
      merged.records[incoming.id] = incoming;
      continue;
    }
    final clock = unionClock(local.clock, incoming.clock);
    Record winner, loser;
    // An edit concurrent with deletion stays available; a subsequent deletion still wins.
    if (local.deleted != incoming.deleted) {
      winner = local.deleted ? incoming : local;
      loser = local.deleted ? local : incoming;
    } else {
      final comparison = '${local.modifiedAt}:${local.digest}'.compareTo(
        '${incoming.modifiedAt}:${incoming.digest}',
      );
      winner = comparison >= 0 ? local : incoming;
      loser = comparison >= 0 ? incoming : local;
    }
    merged.records[incoming.id] = Record(
      id: winner.id,
      modifiedAt: winner.modifiedAt,
      clock: clock,
      recipe: winner.recipe,
    );
    if (local.digest != incoming.digest && !loser.deleted) {
      final conflictId =
          '${incoming.id}:conflict:${loser.digest.substring(0, 16)}';
      final conflict = Record(
        id: conflictId,
        modifiedAt: loser.modifiedAt,
        clock: loser.clock,
        recipe: loser.recipe!.copyWith(
          id: conflictId,
          title: '${loser.recipe!.title} · копия при конфликте',
        ),
      );
      // A deleted/resolved conflict must not be resurrected by another old replica.
      final existing = merged.records[conflictId] ?? b.records[conflictId];
      if (existing == null) merged.records[conflictId] = conflict;
    }
  }
  return merged;
}
