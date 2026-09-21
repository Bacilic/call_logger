// Το «ποιος είσαι» ορίζεται σε **μία πόρτα**: τον `OperatorIdentity`.
//
// Η αναγνώριση γίνεται σκόπιμα χωρίς κωδικούς — απόφαση Διευθυντή 17/09/2026,
// μετά από ζύγισμα του κόστους: η ομάδα είναι μικρή, το Ιστορικό σφραγίζει
// ονομαστικά κάθε ενέργεια, και η βάση κάθεται σε κοινόχρηστο φάκελο όπου
// πραγματική κλειδαριά είναι μόνο τα δικαιώματα των Windows. Άρα τα δικαιώματα
// είναι **ζώνη ασφαλείας από λάθη**, όχι κλειδαριά, και αυτό δηλώνεται ρητά
// στο `PermissionService`.
//
// **Γιατί υπάρχει αυτός ο φρουρός, αφού δεν υπάρχει κωδικός.** Ακριβώς γι'
// αυτό. Η ίδια απόφαση κρίθηκε φθηνά επειδή η ταυτότητα ορίζεται σε ένα σημείο:
// αν κάποτε χρειαστεί κωδικός, μπαίνει εκεί και πουθενά αλλού. Μια δεύτερη
// πόρτα δεν χαλάει τίποτα σήμερα — μεγαλώνει σιωπηλά το κόστος της αυριανής
// απόφασης, και η μία από τις δύο θα ξεχαστεί. Ο φρουρός παγώνει το κόστος.
//
// Ο έλεγχος διαβάζει το **γραπτό όνομα** της κλήσης, όχι τη ροή: κλείνει τον
// δρόμο πριν φτάσει κανείς στην πόρτα.
//
// Το `CurrentOperator.reset()` δεν φυλάγεται εδώ επίτηδες — **αφαιρεί**
// ταυτότητα, δεν δίνει. Καμία παράκαμψη δεν περνά από εκεί.
//
//   flutter test test/architecture/identity_has_one_door_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Η ΠΟΡΤΑ — το μόνο σημείο που αποφασίζει ποιος κάθεται μπροστά στην οθόνη.
const _doorPath = 'lib/core/services/operator_identity.dart';

/// Ο ίδιος ο ορισμός της καθολικής ταυτότητας.
const _definitionPath = 'lib/core/services/current_operator.dart';

/// **Ανανέωση στοιχείων, ΟΧΙ αλλαγή προσώπου** — η μία επιτρεπτή εξαίρεση.
///
/// Όταν ο χρήστης επεξεργάζεται το **δικό του** προφίλ, η ενεργή ταυτότητα
/// ξαναδιαβάζεται ώστε το Ιστορικό να μη συνεχίσει να σφραγίζει με το παλιό
/// όνομα. Το σημείο ελέγχει ρητά `active.id == updated.id`, άρα δεν μπορεί να
/// βάλει κανέναν στη θέση κανενός — δεν είναι δεύτερη πόρτα.
///
/// **Δεν προστίθενται νέες εγγραφές εδώ.** Αν ο έλεγχος σε έφερε σε αυτή τη
/// λίστα, πέρασε την ενεργοποίηση από τον `OperatorIdentity` αντί να μακρύνεις
/// την εξαίρεση.
const _refreshOnlyPaths = <String>{
  'lib/features/operators/services/operator_management.dart',
};

/// Η ενεργοποίηση ταυτότητας, όπως γράφεται στον κώδικα.
final _activation = RegExp(r'CurrentOperator\.activate\s*\(');

/// Ο έλεγχος ταυτοπροσωπίας που κάνει την εξαίρεση ακίνδυνη.
///
/// Χωρίς αυτόν, η «ανανέωση στοιχείων» θα μπορούσε να ενεργοποιήσει άλλον
/// άνθρωπο — και η εξαίρεση θα είχε γίνει δεύτερη πόρτα χωρίς να το πάρει
/// κανείς είδηση.
final _sameIdGuard = RegExp(r'active\.id\s*!=\s*updated\.id');

List<File> _libDartFiles(Directory libRoot) => libRoot
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

String _relative(File file, Directory projectRoot) =>
    p.relative(file.path, from: projectRoot.path).replaceAll(r'\', '/');

/// Οι γραμμές ενεργοποίησης ενός αρχείου, αγνοώντας τα σχόλια.
List<int> _activationLines(File file) {
  final lines = file.readAsStringSync().split('\n');
  final found = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimLeft();
    if (line.startsWith('//')) continue;
    if (_activation.hasMatch(line)) found.add(i + 1);
  }
  return found;
}

void main() {
  final projectRoot = Directory.current;
  final libRoot = Directory(p.join(projectRoot.path, 'lib'));

  setUpAll(() {
    expect(
      libRoot.existsSync(),
      isTrue,
      reason: 'Αναμένεται φάκελος lib/ στο root του project.',
    );
  });

  // Ο έλεγχος στηρίζεται σε regex πάνω στην πηγή. Αν αλλάξει το όνομα της
  // κλήσης, το regex θα έβρισκε ΜΗΔΕΝ ενεργοποιήσεις — και ο φρουρός θα
  // περνούσε πάντα, φυλάγοντας το τίποτα. Αυτό το πιάνει αυτός ο έλεγχος.
  test('η πόρτα διαβάζεται — ο φρουρός δεν φυλάει άδειο σύνολο', () {
    final door = File(p.join(projectRoot.path, _doorPath));
    expect(
      door.existsSync(),
      isTrue,
      reason: 'Δεν βρέθηκε η πόρτα ταυτότητας στο $_doorPath.',
    );
    expect(
      _activationLines(door).length,
      greaterThanOrEqualTo(4),
      reason:
          'Αναμένονται πολλαπλές ενεργοποιήσεις μέσα στην πόρτα (εκκίνηση, '
          'επιλογή, δημιουργία προφίλ). Λιγότερες σημαίνουν ότι άλλαξε η μορφή '
          'της κλήσης και ο φρουρός διαβάζει στο κενό.',
    );
  });

  test('η ταυτότητα ενεργοποιείται ΜΟΝΟ από την πόρτα', () {
    final violations = <String>[];
    final exceptionsSeen = <String>{};

    for (final file in _libDartFiles(libRoot)) {
      final relative = _relative(file, projectRoot);
      if (relative == _doorPath || relative == _definitionPath) continue;

      final lines = _activationLines(file);
      if (lines.isEmpty) continue;

      if (_refreshOnlyPaths.contains(relative)) {
        exceptionsSeen.add(relative);
        continue;
      }
      for (final line in lines) {
        violations.add('$relative:$line — ενεργοποιεί ταυτότητα εκτός πόρτας');
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} σημεία που ορίζουν ταυτότητα έξω από '
        'τον OperatorIdentity.\n'
        'Η ταυτότητα ορίζεται σε ΕΝΑ σημείο: εκκίνηση και «Αλλαγή χρήστη» '
        'περνούν και οι δύο από εκεί.\n'
        'Δεύτερη πόρτα σημαίνει ότι κάθε μελλοντικός έλεγχος στην είσοδο '
        '(κωδικός, προειδοποίηση, μητρώο συνεδριών) θα πρέπει να γραφτεί δύο '
        'φορές — και η μία θα ξεχαστεί:\n'
        '${violations.join('\n')}',
      );
    }

    // Η λίστα εξαιρέσεων αδειάζει: ό,τι πέρασε από την πόρτα φεύγει και από
    // εδώ, αλλιώς η εξαίρεση επιβιώνει του λόγου της και καλύπτει την επόμενη.
    final stale = _refreshOnlyPaths.difference(exceptionsSeen);
    expect(
      stale,
      isEmpty,
      reason:
          'Η λίστα εξαιρέσεων έχει εγγραφές που δεν ενεργοποιούν πια ταυτότητα '
          '— σβήσε τες, ώστε να μην καλύψουν μελλοντική δεύτερη πόρτα: $stale',
    );
  });

  test('η εξαίρεση ανανεώνει τον ΙΔΙΟ, δεν βάζει άλλον στη θέση του', () {
    for (final relative in _refreshOnlyPaths) {
      final source = File(
        p.join(projectRoot.path, relative),
      ).readAsStringSync();
      expect(
        _sameIdGuard.hasMatch(source),
        isTrue,
        reason:
            'Το $relative επιτρέπεται να ενεργοποιεί ταυτότητα ΜΟΝΟ επειδή '
            'ανανεώνει τα στοιχεία του ήδη συνδεδεμένου προσώπου. Χωρίς τον '
            'έλεγχο ταυτοπροσωπίας, η εξαίρεση γίνεται δεύτερη πόρτα.',
      );
    }
  });
}
