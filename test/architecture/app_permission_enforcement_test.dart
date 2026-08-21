import 'dart:io';

import 'package:call_logger/core/models/app_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Κάθε δικαίωμα δηλώνει στον κατάλογο αν επιβάλλεται ([AppPermission.enforced])
/// και η καρτέλα των τικ σημαίνει ορατά όσα δεν επιβάλλονται.
///
/// **Η δήλωση είναι υπόσχεση προς τον διαχειριστή**: «αυτό το τικ πιάνει» ή
/// «αυτό δεν εμποδίζει τίποτα ακόμη». Μια σημαία που ξέμεινε από την
/// πραγματικότητα μετατρέπει την υπόσχεση σε ψέμα — και το ψέμα είναι χειρότερο
/// από την απουσία, γιατί ο διαχειριστής θα νομίζει ότι κλείδωσε κάτι.
///
/// Ο έλεγχος ψάχνει την **κλήση της πύλης** (`can(AppPermission.x)`) και όχι
/// απλή αναφορά στο δικαίωμα: η ίδια η λίστα τικ αναφέρει όλα τα δικαιώματα
/// χωρίς να επιβάλλει κανένα.
void main() {
  test('η σημαία «επιβάλλεται» συμφωνεί με τα σημεία ελέγχου του lib/', () {
    final projectRoot = Directory.current;
    final libRoot = Directory(p.join(projectRoot.path, 'lib'));
    expect(
      libRoot.existsSync(),
      isTrue,
      reason: 'Αναμένεται φάκελος lib/ στο root του project.',
    );

    final sources = libRoot
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    final missingGate = <String>[];
    final undeclaredGate = <String>[];

    for (final permission in AppPermission.values) {
      // `can(` και το δικαίωμα χωρίζονται συχνά σε δύο γραμμές από τη
      // μορφοποίηση, γι' αυτό το `\s*` και το `dotAll` δεν είναι πολυτέλεια.
      final gateCall = RegExp(
        r'can\(\s*AppPermission\.' + permission.name + r'\b',
        multiLine: true,
      );
      final hasGate = gateCall.hasMatch(sources);

      if (permission.enforced && !hasGate) {
        missingGate.add(permission.name);
      }
      if (!permission.enforced && hasGate) {
        undeclaredGate.add(permission.name);
      }
    }

    expect(
      missingGate,
      isEmpty,
      reason:
          'Δηλώνονται ως «επιβάλλονται» αλλά δεν βρέθηκε πουθενά κλήση της '
          'πύλης γι\' αυτά: $missingGate. Η λίστα τικ τα δείχνει ενεργά ενώ '
          'δεν εμποδίζουν τίποτα.',
    );

    expect(
      undeclaredGate,
      isEmpty,
      reason:
          'Έχουν σημείο ελέγχου αλλά δηλώνονται ως «δεν ισχύουν ακόμη»: '
          '$undeclaredGate. Γυρίστε τη σημαία σε enforced: true στο '
          'app_permission.dart, αλλιώς η καρτέλα τα σημαίνει ως ανενεργά '
          'ενώ κλειδώνουν κανονικά.',
    );
  });

  test('τα κλειδιά αποθήκευσης είναι μοναδικά', () {
    final keys = AppPermission.values.map((p) => p.key).toList();
    expect(
      keys.toSet().length,
      keys.length,
      reason:
          'Διπλό κλειδί σημαίνει ότι δύο δικαιώματα γράφονται στην ίδια θέση '
          'του permissions_json και το ένα σβήνει σιωπηλά το άλλο.',
    );
  });
}
