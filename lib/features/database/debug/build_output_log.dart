import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Συσσωρευτής γραμμών εξόδου μεταγλώττισης.
///
/// Συμβόλαιο: **η προσάρτηση κοστίζει το ίδιο στη γραμμή 1 και στη γραμμή
/// 1000.** Γι' αυτό οι γραμμές μένουν χωριστές· δεν συντίθεται ενιαίο κείμενο
/// σε κάθε προσθήκη, ούτε ξαναγράφεται ό,τι έχει ήδη γραφτεί.
///
/// Το ενιαίο κείμενο ([toText]) παράγεται **μόνο όταν ζητηθεί** — π.χ. για
/// αντιγραφή ή σε τεστ.
class BuildOutputLog extends ChangeNotifier {
  final List<String> _lines = <String>[];

  /// Οι γραμμές ως άποψη μόνο-ανάγνωσης (χωρίς αντιγραφή του πίνακα).
  late final List<String> lines = UnmodifiableListView(_lines);

  int get length => _lines.length;
  bool get isEmpty => _lines.isEmpty;

  void append(String line) {
    _lines.add(line);
    notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }

  String toText() => _lines.join('\n');
}
