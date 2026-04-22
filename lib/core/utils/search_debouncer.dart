import 'dart:async';

/// Μικρός βοηθός αναζήτησης με debounce + αύξοντα αριθμό αιτήματος (request-seq).
///
/// Αποφεύγει race conditions όταν εκκρεμούν πολλαπλές ασύγχρονες αναζητήσεις: το
/// [run] ενσωματώνει το κείμενο σε μια κλήση αφού σταματήσει να αλλάζει για
/// [delay] χρόνο, ενώ η μέθοδος [runImmediate] εκτελεί άμεσα (π.χ. σε onSubmitted)
/// παρακάμπτοντας το timer αλλά χρησιμοποιώντας το ίδιο sequencing.
///
/// Υπόδειγμα χρήσης (State μέσα σε widget):
///
/// ```dart
/// final _debouncer = SearchDebouncer();
///
/// @override
/// void dispose() {
///   _debouncer.dispose();
///   super.dispose();
/// }
///
/// void _onTextChanged(String value) {
///   _debouncer.run(value, (q, isCurrent) async {
///     final results = await repo.search(q);
///     if (!isCurrent()) return;
///     setState(() => _hits = results);
///   });
/// }
/// ```
class SearchDebouncer {
  SearchDebouncer({this.delay = const Duration(milliseconds: 220)});

  final Duration delay;

  Timer? _timer;
  int _seq = 0;
  bool _disposed = false;

  /// Τρέχον sequence number. Η [callback] λαμβάνει [isCurrent] για να ελέγχει
  /// αν η ίδια η εκτέλεση παραμένει η «τρέχουσα» (κάθε νέα κλήση αυξάνει το seq).
  bool Function() _makeIsCurrent(int ownSeq) =>
      () => !_disposed && _seq == ownSeq;

  /// Προγραμματίζει την [callback] μετά από [delay] (ακυρώνοντας προηγούμενη).
  /// Κάθε κλήση αυξάνει το sequence — χρησιμοποίησε [isCurrent] στο callback
  /// πριν εφαρμόσεις αποτελέσματα (π.χ. `setState`).
  void run(
    String query,
    Future<void> Function(String q, bool Function() isCurrent) callback,
  ) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final ownSeq = ++_seq;
      callback(query, _makeIsCurrent(ownSeq));
    });
  }

  /// Άμεση εκτέλεση (π.χ. onSubmitted) παρακάμπτοντας το debounce timer, αλλά
  /// διατηρώντας το sequencing ώστε να μην εφαρμοστούν stale αποτελέσματα.
  Future<void> runImmediate(
    String query,
    Future<void> Function(String q, bool Function() isCurrent) callback,
  ) async {
    if (_disposed) return;
    _timer?.cancel();
    final ownSeq = ++_seq;
    await callback(query, _makeIsCurrent(ownSeq));
  }

  /// Ακύρωση εκκρεμούς timer και των αποτελεσμάτων τρέχοντος αιτήματος.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _seq++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
