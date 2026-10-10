// Quantities are recognized independently of the ingredient's layout. Names,
// percentages, cooking temperatures and the size of each package stay intact.
const _fractions = <String, double>{
  '½': 1 / 2,
  '¼': 1 / 4,
  '¾': 3 / 4,
  '⅓': 1 / 3,
  '⅔': 2 / 3,
  '⅛': 1 / 8,
  '⅜': 3 / 8,
  '⅝': 5 / 8,
  '⅞': 7 / 8,
  '⅕': 1 / 5,
  '⅖': 2 / 5,
  '⅗': 3 / 5,
  '⅘': 4 / 5,
  '⅙': 1 / 6,
  '⅚': 5 / 6,
  '⅐': 1 / 7,
  '⅑': 1 / 9,
  '⅒': 1 / 10,
};
const _wordNumbers = <String, double>{
  'ноль': 0,
  'один': 1,
  'одна': 1,
  'одно': 1,
  'одну': 1,
  'одного': 1,
  'одной': 1,
  'два': 2,
  'две': 2,
  'двух': 2,
  'три': 3,
  'трех': 3,
  'четыре': 4,
  'пять': 5,
  'шесть': 6,
  'семь': 7,
  'восемь': 8,
  'девять': 9,
  'десять': 10,
  'одиннадцать': 11,
  'двенадцать': 12,
  'тринадцать': 13,
  'четырнадцать': 14,
  'пятнадцать': 15,
  'шестнадцать': 16,
  'семнадцать': 17,
  'восемнадцать': 18,
  'девятнадцать': 19,
  'двадцать': 20,
  'тридцать': 30,
  'сорок': 40,
  'пятьдесят': 50,
  'шестьдесят': 60,
  'семьдесят': 70,
  'восемьдесят': 80,
  'девяносто': 90,
  'сто': 100,
  'двести': 200,
  'триста': 300,
  'четыреста': 400,
  'пятьсот': 500,
  'шестьсот': 600,
  'семьсот': 700,
  'восемьсот': 800,
  'девятьсот': 900,
  'тысяча': 1000,
  'тысячи': 1000,
  'тысяч': 1000,
  'полтора': 1.5,
  'полторы': 1.5,
  'половина': .5,
  'половину': .5,
  'половины': .5,
  'четверть': .25,
};
const _implicitUnits = <String, String>{
  'поллитра': 'л',
  'полкило': 'кг',
  'полкилограмма': 'кг',
  'полстакана': 'стакан',
};
final _number = RegExp(
  r'\d+(?:[.,]\d+)?[eE][+-]?\d+|'
  r'\d+\s+\d+\s*[/⁄]\s*\d+|\d+\s*[/⁄]\s*\d+|'
  r'(?:\d+\s*)?[½¼¾⅓⅔⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚⅐⅑⅒]|'
  r'\d{1,3}(?:[ \u00a0\u202f]\d{3})+(?:[.,]\d+)?|'
  r'\d+(?:[.,]\d+)+|\d+|(?<![\p{L}\p{N}])[.,]\d+',
  unicode: true,
);
final _spoken = RegExp(
  '(?<![\\p{L}])(?:${_implicitUnits.keys.join('|')}|'
  '(?:${_wordNumbers.keys.join('|')})(?:\\s+(?:${_wordNumbers.keys.join('|')}))*)(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
const _unitSource =
    r'(?:(?:ст|ч)\.?\s*/?\s*л\.?|(?:ст|ч)\.\s*лож(?:ка|ки|ек|ку)|стол(?:овая|овой|овые|овых)?\s+лож(?:ка|ки|ек|ку)|'
    r'чайн(?:ая|ой|ые|ых)\s+лож(?:ка|ки|ек|ку)|десертн(?:ая|ой)\s+лож(?:ка|ки|ек)|'
    r'килограмм(?:а|ов)?|миллиграмм(?:а|ов)?|грамм(?:а|ов)?|кг|мг|гр\.?|г|'
    r'миллилитр(?:а|ов)?|сантилитр(?:а|ов)?|децилитр(?:а|ов)?|литр(?:а|ов)?|мл|сл|дл|л|'
    r'стакан(?:а|ов)?|чашк(?:а|и|у)|лож(?:ка|ки|ек|ку)|шт\.?|штук(?:а|и)?|'
    r'голов(?:ка|ки|ок|ку)|зубчик(?:а|ов)?|яйц(?:о|а)?|яиц|желт(?:ок|ка|ков)|бел(?:ок|ка|ков)|пуч(?:ок|ка|ков)|веточ(?:ка|ки|ек)|'
    r'дол(?:я|и|ей)|дол(?:ька|ьки|ек)|кус(?:ок|ка|ков)|ломтик(?:а|ов)?|'
    r'щепот(?:ка|ки|ок|ку)|горст(?:ь|и|ей)|кап(?:ля|ли|ель)|палоч(?:ка|ки|ек)|'
    r'лист(?:а|ов)?|пластин(?:ка|ки|ок)|струч(?:ок|ка|ков)|'
    r'бан(?:ка|ки|ок|ку)|пач(?:ка|ки|ек|ку)|упаков(?:ка|ки|ок|ку)|'
    r'пакет(?:ик)?(?:а|ов)?|бутыл(?:ка|ки|ок|ку)|короб(?:ка|ки|ок)|тюбик(?:а|ов)?|'
    r'fl\.?\s*oz\.?|tbsp\.?|tsp\.?|cups?|tablespoons?|teaspoons?|'
    r'kg|mg|g|gr\.?|grams?|kilograms?|ml|cl|dl|l|liters?|litres?|oz\.?|ounces?|lb\.?|lbs\.?|pounds?|'
    r'pieces?|pcs\.?|cloves?|cans?|packs?|packages?|bottles?)';
final _unit = RegExp(
  '^\\s*($_unitSource)(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _unitBefore = RegExp(
  '(?<![\\p{L}])($_unitSource)\\s*\$',
  caseSensitive: false,
  unicode: true,
);
final _package = RegExp(
  r'^(?:бан|пач|упаков|пакет|бутыл|короб|тюбик|can|pack|bottle)',
  caseSensitive: false,
);
final _notQuantity = RegExp(
  r'^\s*(?:%|°|процент|градус|минут|мин\.?(?!\p{L})|секунд|сек\.?(?!\p{L})|час|сут|дн|день|недел|месяц|год|лет|'
  r'сорт|категори|ккал|кдж|kcal|kj|порц|(?:см|mm|cm|мм)(?!\p{L}))',
  caseSensitive: false,
  unicode: true,
);
final _composition = RegExp(
  r'^\s*(?:сыра|сыров|злаков|специй|перцев|трав|семян)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);
final _countedFood = RegExp(
  r'(?:яйц|желтк|белк|чеснок|картоф|морков|яблок|лимон|банан|томат|помидор|огурец|кабач|баклажан|апельсин|авокадо|свекл|свёкл)',
  caseSensitive: false,
);
final _nameNumber = RegExp(
  r'(?:№|номер|сорт(?:а)?|категори\p{L}*|тип(?:а)?)\s*[-:]?\s*$',
  caseSensitive: false,
  unicode: true,
);
final _range = RegExp(r'^\s*(?:[–—−-]|до|to)\s*$', caseSensitive: false);

class _Amount {
  final int start, end;
  final double number;
  final String? implicitUnit;
  String unit = '';
  bool scale = false, fixed = false;
  _Amount(this.start, this.end, this.number, {this.implicitUnit});
}

double? _readNumber(String raw) {
  var value = raw.trim();
  final fraction =
      _fractions[value.isEmpty ? '' : value.substring(value.length - 1)];
  if (fraction != null) {
    final whole = value.substring(0, value.length - 1).trim();
    return (whole.isEmpty ? 0 : double.parse(whole)) + fraction;
  }
  final slash = RegExp(
    r'^(?:(\d+)\s+)?(\d+)\s*[/⁄]\s*(\d+)$',
  ).firstMatch(value);
  if (slash != null) {
    final denominator = double.parse(slash[3]!);
    if (denominator == 0) return null;
    return double.parse(slash[1] ?? '0') +
        double.parse(slash[2]!) / denominator;
  }
  value = value.replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');
  if (value.contains(',') && value.contains('.')) {
    final decimal = value.lastIndexOf(',') > value.lastIndexOf('.') ? ',' : '.';
    value = value
        .replaceAll(decimal == ',' ? '.' : ',', '')
        .replaceAll(decimal, '.');
  } else {
    final marks = RegExp(r'[.,]').allMatches(value).length;
    // Multiple grouping marks are unambiguous; a single comma is decimal.
    value = marks > 1
        ? value.replaceAll(RegExp(r'[.,]'), '')
        : value.replaceAll(',', '.');
  }
  return double.tryParse(value.startsWith('.') ? '0$value' : value);
}

double? _readWords(String value) {
  var total = 0.0, group = 0.0, previous = double.infinity;
  for (final word
      in value.toLowerCase().replaceAll('ё', 'е').split(RegExp(r'\s+'))) {
    final n = _wordNumbers[word];
    if (n == null) return null;
    if (n == 1000) {
      total += (group == 0 ? 1 : group) * n;
      group = 0;
      previous = double.infinity;
    } else {
      if (n >= previous || previous < 20) return null;
      group += n;
      previous = n;
    }
  }
  return total + group;
}

String _scaledNumber(double value) => value
    .toStringAsFixed(6)
    .replaceFirst(RegExp(r'\.?0+$'), '')
    .replaceAll('.', ',');

String scaleIngredient(String value, double factor) {
  if (factor <= 0 || !factor.isFinite) throw ArgumentError('Invalid portions');
  if (factor == 1) return value;
  final amounts = <_Amount>[];
  for (final match in _number.allMatches(value)) {
    final number = _readNumber(match[0]!);
    if (number != null && number.isFinite) {
      amounts.add(_Amount(match.start, match.end, number));
    }
  }
  for (final match in _spoken.allMatches(value)) {
    final word = match[0]!.toLowerCase().replaceAll('ё', 'е');
    final implicit = _implicitUnits[word];
    final number = implicit == null ? _readWords(word) : .5;
    if (number != null) {
      amounts.add(
        _Amount(match.start, match.end, number, implicitUnit: implicit),
      );
    }
  }
  amounts.sort((a, b) => a.start.compareTo(b.start));
  for (var i = 0; i < amounts.length; i++) {
    final amount = amounts[i];
    final extra = RegExp(
      r'^\s+с\s+(половиной|четвертью|третью)(?!\p{L})',
      unicode: true,
      caseSensitive: false,
    ).firstMatch(value.substring(amount.end));
    if (extra != null) {
      final fraction = switch (extra[1]!.toLowerCase()) {
        'половиной' => .5,
        'четвертью' => .25,
        _ => 1 / 3,
      };
      amounts[i] = _Amount(
        amount.start,
        amount.end + extra.end,
        amount.number + fraction,
      );
    }
  }
  for (final amount in amounts) {
    final before = value.substring(0, amount.start),
        after = value.substring(amount.end);
    if (_notQuantity.hasMatch(after) ||
        _composition.hasMatch(after) ||
        _nameNumber.hasMatch(before)) {
      amount.fixed = true;
      continue;
    }
    final unit =
        _unit.firstMatch(after)?.group(1) ??
        _unitBefore.firstMatch(before)?.group(1);
    amount.unit = unit ?? amount.implicitUnit ?? '';
    final atStart = RegExp(
      r'^\s*[-•*–—]?\s*(?:около|примерно|от|~|≈)?\s*$',
      caseSensitive: false,
    ).hasMatch(before);
    final afterSeparator = RegExp(
      r'(?:[,;:：=]|\s[–—-]|[–—-]\s)\s*(?:около|примерно|~|≈)?\s*$',
      caseSensitive: false,
    ).hasMatch(before);
    final bareCount =
        _countedFood.hasMatch(before) &&
        RegExp(r'^\s*[)\]]?\s*$').hasMatch(after);
    final inBrackets =
        RegExp(r'[(\[]\s*$').hasMatch(before) &&
        RegExp(r'^\s*(?:[)\]]|[–—−-]|до)').hasMatch(after);
    final ordinal =
        atStart &&
        RegExp(r'^[.)](?:\s|(?=\p{L}))', unicode: true).hasMatch(after);
    amount.scale =
        !ordinal &&
        (amount.unit.isNotEmpty ||
            atStart ||
            afterSeparator ||
            bareCount ||
            inBrackets);
  }
  // A range inherits the measured unit from its endpoint. A package's own
  // size is fixed: 2 cans × 400 g becomes 4 cans × 400 g, never 4 × 800 g.
  for (var i = 1; i < amounts.length; i++) {
    final previous = amounts[i - 1], current = amounts[i];
    final between = value.substring(previous.end, current.start);
    if (RegExp(r'^\s*:\s*$').hasMatch(between)) {
      // Ratios and timestamps are attributes, not measured amounts.
      previous.fixed = current.fixed = true;
    } else if (RegExp(
          r'^\s*[×xх*]\s*$',
          caseSensitive: false,
        ).hasMatch(between) &&
        current.scale &&
        !previous.fixed) {
      previous.scale = true;
      current.fixed = true;
    } else if (_package.hasMatch(previous.unit) &&
        (RegExp(
              r'(?:(?<!\p{L})по|[×xх*]|весом|массой|объемом|объёмом)\s*\(?\s*$',
              caseSensitive: false,
              unicode: true,
            ).hasMatch(between) ||
            (between.contains('(') &&
                RegExp(
                  '^\\s*$_unitSource\\s+(?:кажд|each)',
                  caseSensitive: false,
                ).hasMatch(value.substring(current.end))))) {
      current.fixed = true;
    }
  }
  // Propagate in both directions, including fractional and spoken endpoints.
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < amounts.length; i++) {
      final a = amounts[i - 1], b = amounts[i];
      if (!_range.hasMatch(value.substring(a.end, b.start))) continue;
      if (a.fixed || b.fixed) {
        a.fixed = b.fixed = true;
      } else if (a.scale || b.scale) {
        a.scale = b.scale = true;
      }
    }
  }
  var result = value;
  for (final amount in amounts.reversed) {
    if (!amount.scale || amount.fixed) continue;
    final scaled = amount.number * factor;
    if (!scaled.isFinite) continue;
    final text =
        '${_scaledNumber(scaled)}${amount.implicitUnit == null ? '' : ' ${amount.implicitUnit}'}';
    result = result.replaceRange(amount.start, amount.end, text);
  }
  return result;
}
