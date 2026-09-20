// Κάθε προσωπικό κλειδί έχει **μία πόρτα**: το `ScopedSettings`.
//
// Ο κατάλογος των προσωπικών κλειδιών ελεγχόταν ήδη για διπλά ονόματα και για
// ρητά δηλωμένη κληρονομιά — αλλά κανείς δεν ρωτούσε το πιο κρίσιμο: **το
// διαβάζει κανείς από τη λάθος πόρτα;** Ένα κλειδί μπορεί να είναι δηλωμένο
// προσωπικό και ταυτόχρονα να γράφεται κατευθείαν στα κοινά `app_settings` ή
// στις τοπικές ρυθμίσεις. Τότε η εφαρμογή πιστεύει ότι η ρύθμιση ακολουθεί
// τον χρήστη, ενώ στην πράξη ο ένας πατά τον άλλον — σιωπηλά, χωρίς σφάλμα
// ούτε προειδοποίηση.
//
// **Το σημάδι είναι πάντα το ίδιο:** το όνομα του κλειδιού γραμμένο δεύτερη
// φορά, έξω από τον κατάλογο. Για να χτυπήσει κανείς την παλιά αποθήκη
// χρειάζεται το ωμό κείμενο — και όποιος το γράφει δεύτερη φορά φτιάχνει
// δεύτερη πηγή αλήθειας για το «πού ζει αυτό;». Γι' αυτό ο φρουρός ελέγχει το
// **γραπτό όνομα**, όχι την κλήση: κλείνει τον δρόμο πριν φτάσει κανείς στην
// πόρτα.
//
//   flutter test test/architecture/profile_settings_single_door_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Το αρχείο που ΕΙΝΑΙ ο κατάλογος — εκεί το λιτεράλ είναι στη θέση του.
const _catalogPath = 'lib/core/services/profile_settings.dart';

/// Η ίδια η πύλη: μόνο αυτή επιτρέπεται να ξετυλίγει κλειδί σε ωμό όνομα.
const _gatePaths = <String>{
  _catalogPath,
  'lib/core/services/scoped_settings.dart',
};

/// ΧΡΕΟΣ — **άδειο**. Τα επτά τελευταία αδρανή διπλόγραφα έφυγαν στις
/// 18/09/2026 και ο φρουρός φυλάει πλέον χωρίς καμία εξαίρεση.
///
/// Ο χάρτης μένει εδώ γιατί κρατά τον έλεγχο «μπαγιάτικης εξαίρεσης» ζωντανό:
/// ό,τι μπει, οφείλει να φύγει. ΔΕΝ προστίθενται νέες εγγραφές — αν ο έλεγχος
/// σε έφερε εδώ, πέρασε την ανάγνωση και την εγγραφή από το `ScopedSettings`
/// αντί να μακρύνεις τη λίστα.
const _debt = <String, Set<String>>{};

/// Τα κλειδιά όπως τα δηλώνει ο κατάλογος, διαβασμένα από την ίδια την πηγή.
final _keyDeclaration = RegExp("ProfileSettingKey\\(\\s*'([a-z0-9_]+)'");

/// Πλάγια πόρτα χωρίς λιτεράλ: `ProfileSettingKeys.κάτι.key`.
final _rawNameEscape = RegExp(r'ProfileSettingKeys\.\w+\.key\b');

List<File> _libDartFiles(Directory libRoot) => libRoot
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

String _relative(File file, Directory projectRoot) =>
    p.relative(file.path, from: projectRoot.path).replaceAll(r'\', '/');

Set<String> _declaredKeys(Directory projectRoot) {
  final source = File(
    p.join(projectRoot.path, _catalogPath),
  ).readAsStringSync();
  final start = source.indexOf('abstract final class ProfileSettingKeys');
  expect(
    start,
    greaterThan(-1),
    reason: 'Δεν βρέθηκε ο κατάλογος ProfileSettingKeys στο $_catalogPath.',
  );
  return _keyDeclaration
      .allMatches(source.substring(start))
      .map((m) => m.group(1)!)
      .toSet();
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

  // Ο έλεγχος στηρίζεται σε regex πάνω στην πηγή. Αν αλλάξει η μορφή του
  // καταλόγου, το regex θα έβρισκε ΜΗΔΕΝ κλειδιά — και ο φρουρός θα περνούσε
  // πάντα, φυλάγοντας το τίποτα. Αυτό το πιάνει αυτός ο έλεγχος.
  test('ο κατάλογος διαβάζεται — ο φρουρός δεν φυλάει άδειο σύνολο', () {
    expect(
      _declaredKeys(projectRoot).length,
      greaterThan(40),
      reason:
          'Αναμένονται δεκάδες προσωπικά κλειδιά. Λιγότερα σημαίνουν ότι άλλαξε '
          'η μορφή του καταλόγου και ο φρουρός διαβάζει στο κενό.',
    );
  });

  test('το όνομα προσωπικού κλειδιού γράφεται ΜΟΝΟ στον κατάλογο', () {
    final keys = _declaredKeys(projectRoot);
    final violations = <String>[];
    final debtSeen = <String, Set<String>>{};

    for (final file in _libDartFiles(libRoot)) {
      final relative = _relative(file, projectRoot);
      if (relative == _catalogPath) continue;
      final content = file.readAsStringSync();
      final allowed = _debt[relative] ?? const <String>{};

      for (final key in keys) {
        final index = content.indexOf("'$key'");
        if (index < 0) continue;
        if (allowed.contains(key)) {
          debtSeen.putIfAbsent(relative, () => <String>{}).add(key);
          continue;
        }
        final lineNo = '\n'.allMatches(content.substring(0, index)).length + 1;
        violations.add(
          "$relative:$lineNo — το προσωπικό κλειδί '$key' γράφεται και εδώ",
        );
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} κλειδιά με δεύτερη γραπτή θέση.\n'
        'Ένα προσωπικό κλειδί δηλώνεται μόνο στο $_catalogPath και '
        'χρησιμοποιείται μόνο μέσω ScopedSettings — π.χ. '
        'ScopedSettings.getString(ProfileSettingKeys.x).\n'
        'Δεύτερο ωμό όνομα σημαίνει ότι κάποιος μπορεί να χτυπήσει την παλιά '
        'αποθήκη, και τότε η ρύθμιση παύει σιωπηλά να ακολουθεί τον χρήστη:\n'
        '${violations.join('\n')}',
      );
    }

    // Η λίστα χρέους αδειάζει: ό,τι διορθώθηκε φεύγει και από εδώ, αλλιώς η
    // εξαίρεση επιβιώνει του λόγου της και καλύπτει την επόμενη υποτροπή.
    final stale = <String>[];
    _debt.forEach((path, allowedKeys) {
      final seen = debtSeen[path] ?? const <String>{};
      for (final key in allowedKeys) {
        if (!seen.contains(key)) stale.add("$path — '$key'");
      }
    });
    expect(
      stale,
      isEmpty,
      reason:
          'Η λίστα χρέους έχει εγγραφές που δεν ισχύουν πια — σβήσε τες, ώστε '
          'να μην καλύψουν μελλοντική υποτροπή.',
    );
  });

  test('κανείς δεν ξετυλίγει κλειδί σε ωμό όνομα έξω από την πύλη', () {
    final violations = <String>[];

    for (final file in _libDartFiles(libRoot)) {
      final relative = _relative(file, projectRoot);
      if (_gatePaths.contains(relative)) continue;
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (_rawNameEscape.hasMatch(lines[i])) {
          violations.add('$relative:${i + 1} — ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Το `.key` βγάζει το ωμό όνομα και επιτρέπει πρόσβαση χωρίς την πύλη '
          '— η ίδια διαρροή με το δεύτερο λιτεράλ, χωρίς καν το λιτεράλ:\n'
          '${violations.join('\n')}',
    );
  });
}
