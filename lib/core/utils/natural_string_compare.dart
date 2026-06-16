/// Φυσική (αλφαριθμητική) σύγκριση κειμένου: `2` πριν το `10` (σε αντίθεση με απλή λεξικογραφική).
int naturalCompareStrings(
  String a,
  String b, {
  bool ignoreCase = true,
}) {
  final sa = ignoreCase ? a.toLowerCase() : a;
  final sb = ignoreCase ? b.toLowerCase() : b;
  var ia = 0;
  var ib = 0;
  while (ia < sa.length && ib < sb.length) {
    final ca = sa.codeUnitAt(ia);
    final cb = sb.codeUnitAt(ib);
    final da = _isAsciiDigit(ca);
    final db = _isAsciiDigit(cb);
    if (da && db) {
      final na = _readInt(sa, ia);
      final nb = _readInt(sb, ib);
      ia = na.nextIndex;
      ib = nb.nextIndex;
      final cmp = na.value.compareTo(nb.value);
      if (cmp != 0) return cmp;
      continue;
    }
    final cmp = ca.compareTo(cb);
    if (cmp != 0) return cmp;
    ia++;
    ib++;
  }
  return sa.length.compareTo(sb.length);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

({int value, int nextIndex}) _readInt(String s, int start) {
  var value = 0;
  var i = start;
  while (i < s.length && _isAsciiDigit(s.codeUnitAt(i))) {
    value = value * 10 + (s.codeUnitAt(i) - 48);
    i++;
  }
  return (value: value, nextIndex: i);
}
