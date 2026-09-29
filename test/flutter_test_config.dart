import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:path/path.dart' as p;

/// Κοινή ρύθμιση για όλα τα τεστ στο `test/`: όριο κολλήματος, θέση προσωρινών
/// αρχείων και leak tracking.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _limitHangingWidgetTests();
  _keepTemporaryFilesOnProjectDrive();
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings.withIgnored(
    // Διάρκεια ζωής διεργασίας: singleton για παγκόσμια οθόνη σφάλματος
    // (`lib/core/widgets/global_fatal_error_notifier.dart`), όχι ανά-widget πόρος.
    //
    // `TextPainter` (ΑΚΡΙΒΩΣ ΕΝΑΣ): τον δημιουργεί το πακέτο `custom_mouse_cursor`
    // μέσα στο `CustomMouseCursor.icon` για να ζωγραφίσει το εικονίδιο του native
    // δείκτη, και δεν τον αποδεσμεύει — δεν έχουμε πρόσβαση σ' αυτόν. Ο δείκτης
    // φορτώνεται μία φορά ανά διεργασία (`_ReorderHandCursor._future ??= ...` στο
    // `lib/core/widgets/reorder_grab_handle.dart`), οπότε η διαρροή είναι σταθερά
    // μία. Το όριο μένει σκόπιμα στο 1: δεύτερος αδέσποτος `TextPainter` θα ήταν
    // δικός μας και ΠΡΕΠΕΙ να κοκκινίσει.
    // `ValueNotifier<Operator?>`: singleton ταυτότητας χρήστη
    // (`lib/core/services/current_operator.dart`) — ζει όσο η διεργασία, ώστε
    // η ένδειξη στη μπάρα να παρακολουθεί ζωντανά την «Αλλαγή χρήστη».
    notDisposed: {
      'ValueNotifier<FatalErrorState?>': null,
      'ValueNotifier<Operator?>': null,
      'TextPainter': 1,
    },
    // Singleton παλέτας τμημάτων + Flutter ImageCache (decode εικόνων στο framework).
    classes: [
      'DepartmentPaletteStore',
      'Image',
      'ImageInfo',
      'ImageStreamCompleterHandle',
      '_CachedImage',
    ],
  );
  await testMain();
}

/// Ένα `testWidgets` που κρεμάει κόβεται στα 2 λεπτά αντί για τα 10 του Flutter.
///
/// Κρέμασμα σημαίνει σχεδόν πάντα αναμονή που δεν τελειώνει ποτέ (διάλογος που
/// κανείς δεν απαντά, κανάλι συστήματος μέσα σε πλαστό χρόνο). Με 10 λεπτά ανά
/// τεστ, ένα αρχείο με πέντε τέτοια τεστ έτρωγε σχεδόν μία ώρα πριν βγει κόκκινο.
/// Το πιο αργό τεστ οθόνης που μετρήθηκε (29/09/2026) θέλει ~9 δευτερόλεπτα στο
/// γρήγορο μηχάνημα· τα 2 λεπτά αφήνουν περιθώριο και για το αργό. Όποιο τεστ
/// δηλώνει δικό του `timeout` το κρατά.
///
/// Το binding στήνεται εδώ για κάθε αρχείο, γιατί το `testWidgets` διαβάζει το
/// όριο τη στιγμή που δηλώνεται το τεστ — αργότερα είναι ήδη αργά.
void _limitHangingWidgetTests() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(minutes: 2));
  }
}

/// Τα προσωρινά αρχεία των τεστ (κυρίως οι δοκιμαστικές βάσεις SQLite) γράφονται
/// στον δίσκο του έργου, στο `build/test_tmp`, αντί για τον φάκελο του συστήματος.
///
/// Μετρημένο 29/09/2026 στο γρήγορο μηχάνημα: κάθε αυτόνομη εγγραφή SQLite
/// θέλει ~9ms στον C: και ~2,6ms στον F:· ο φάκελος `test/core/database/` έπεσε
/// από 122–132s σε 58–62s. Τα τεστ δεν αλλάζουν — μόνο ο δίσκος όπου γράφουν.
/// Αν ο φάκελος δεν στήνεται, μένει ο φάκελος του συστήματος.
void _keepTemporaryFilesOnProjectDrive() {
  final dir = Directory(p.join(Directory.current.path, 'build', 'test_tmp'));
  try {
    dir.createSync(recursive: true);
  } on FileSystemException {
    return;
  }
  _sweepStaleLeftovers(dir);
  IOOverrides.global = _ProjectDriveTemp(dir);
}

/// Σβήνει ό,τι άφησαν πίσω παλαιότερα τρεξίματα (τεστ που δεν καθάρισαν ή
/// κόπηκαν). Μόνο ό,τι είναι πάνω από μία μέρα: τα αρχεία που τρέχουν παράλληλα
/// τώρα έχουν φρέσκους φακέλους και δεν αγγίζονται.
void _sweepStaleLeftovers(Directory dir) {
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      try {
        if (entity.statSync().modified.isBefore(cutoff)) {
          entity.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Τον σβήνει ταυτόχρονα άλλο αρχείο τεστ, ή είναι ακόμη σε χρήση.
      }
    }
  } on FileSystemException {
    // Το καθάρισμα είναι ευκολία· ποτέ λόγος να μην τρέξει το τεστ.
  }
}

final class _ProjectDriveTemp extends IOOverrides {
  _ProjectDriveTemp(this._dir);

  final Directory _dir;

  @override
  Directory getSystemTempDirectory() => _dir;
}
