import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Κοινή ρύθμιση για όλα τα τεστ στο `test/` — ενεργοποίηση leak tracking.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
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
    notDisposed: {'ValueNotifier<AppErrorResult?>': null, 'TextPainter': 1},
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
