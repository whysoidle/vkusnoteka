String countLabel(int count, String one, String few, String many) {
  final mod100 = count.abs() % 100, mod10 = count.abs() % 10;
  final word = mod100 >= 11 && mod100 <= 14
      ? many
      : mod10 == 1
      ? one
      : mod10 >= 2 && mod10 <= 4
      ? few
      : many;
  return '$count $word';
}
