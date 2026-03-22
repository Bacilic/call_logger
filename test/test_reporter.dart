/// Συγκεντρωτική αναφορά δοκιμών στα ελληνικά (custom reporter helpers).
library;

/// Καταγραφή ενός ελέγχου για τελική αναφορά.
class GreekTestCheckRecord {
  GreekTestCheckRecord({
    required this.name,
    required this.passed,
    this.hint,
  });

  final String name;
  final bool passed;
  final String? hint;
}

/// Συλλέκτης αποτελεσμάτων για εκτύπωση στο τέλος των ομάδων δοκιμών.
class GreekTestReportCollector {
  GreekTestReportCollector();

  final List<GreekTestCheckRecord> _records = <GreekTestCheckRecord>[];

  void recordPass(String name) {
    _records.add(GreekTestCheckRecord(name: name, passed: true));
    // ignore: avoid_print
    print('✅ Πέρασε: $name');
  }

  void recordFail(String name, {String? hint}) {
    _records.add(
      GreekTestCheckRecord(name: name, passed: false, hint: hint),
    );
    // ignore: avoid_print
    print('❌ Απέτυχε: $name${hint != null ? ' — $hint' : ''}');
  }

  /// Χρονόμετρο για μήνυμα απόδοσης (lookup κ.λπ.).
  void logTiming(String label, Duration duration) {
    final ms = duration.inMilliseconds;
    // ignore: avoid_print
    print('⏱️ $label: ${ms}ms');
  }

  /// Βήμα ροής widget/integration (ελληνικά μηνύματα στο τερματικό).
  void logStep(String message) {
    // ignore: avoid_print
    print('✅ $message');
  }

  void printFinalSummary({String title = 'Συγκεντρωτική αναφορά δοκιμών'}) {
    final total = _records.length;
    final passed = _records.where((r) => r.passed).length;
    final failed = total - passed;
    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('════════════════════════════════════════')
      ..writeln('📋 $title')
      ..writeln('════════════════════════════════════════');
    if (total == 0) {
      buffer.writeln(
        'ℹ️ Δεν καταγράφηκαν ρητοί έλεγχοι (recordPass / recordFail).',
      );
    } else {
      buffer.writeln('✅ Καταγεγραμμένοι έλεγχοι: $passed / $total πέρασαν');
      if (failed > 0) {
        buffer.writeln('❌ Αποτυχίες (στην αναφορά): $failed');
        buffer.writeln('— Λεπτομέρειες:');
        for (final r in _records.where((e) => !e.passed)) {
          buffer.writeln('  • ${r.name}');
          if (r.hint != null) {
            buffer.writeln('    Προτεινόμενη διόρθωση: ${r.hint}');
          }
        }
      } else {
        buffer.writeln(
          '🎉 Όλοι οι καταγεγραμμένοι έλεγχοι (στην αναφορά) ολοκληρώθηκαν επιτυχώς.',
        );
      }
    }
    buffer.writeln(
      '— Σημείωση: Το τελικό pass/fail της δοκιμής καθορίζεται από το Flutter test '
      'runner (γραμμές +N -M και [E]), όχι από αυτή την αναφορά· εδώ μετριούνται '
      'μόνο οι ρητές κλήσεις recordPass/recordFail.',
    );
    buffer.writeln('════════════════════════════════════════');
    // ignore: avoid_print
    print(buffer.toString());
  }

  void clear() => _records.clear();
}

/// Μήνυμα για expect (χρήση ως reason / failure description).
String greekExpectMsg(String description) => description;
