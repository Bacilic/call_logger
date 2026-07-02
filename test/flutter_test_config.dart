import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Κοινή ρύθμιση για όλα τα τεστ στο `test/` — ενεργοποίηση leak tracking.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings.withIgnored(
    // Διάρκεια ζωής διεργασίας: singleton για παγκόσμια οθόνη σφάλματος
    // (`lib/core/widgets/global_fatal_error_notifier.dart`), όχι ανά-widget πόρος.
    notDisposed: {'ValueNotifier<AppErrorResult?>': null},
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
