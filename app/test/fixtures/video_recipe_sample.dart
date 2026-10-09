import 'package:recipe_vault/services/video_recipe_parser.dart';

const description = '''Сегодня два варианта теста. Подписывайтесь!
https://example.com

Рецепт теста на молоке
Молоко 400 мл
Мука 180 граммов
Яйца 2 штуки
Масло 2 столовые ложки

Рецепт теста на воде:
Вода 300 мл
Мука 250 г
Яйца 3 шт.
Соль по вкусу

Подписка: 100 рублей
https://example.com/support
''';

final outlines = videoRecipeOutlines(
  description,
  title: 'Два варианта',
  sourceUrl: 'https://youtu.be/abcdefghijk',
);
