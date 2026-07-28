// Το «παγιδευμένο παράθυρο»: όσο το preventClose είναι οπλισμένο, ΚΑΘΕ οθόνη
// πρέπει να έχει χειριστή κλεισίματος — όχι μόνο το κύριο κέλυφος.
//
// Πριν τη διόρθωση, ο μοναδικός χειριστής ζούσε μέσα στο AppShortcuts: μόλις
// αυτό αντικαθιστόταν (σφάλμα βάσης, φόρτωση, εκκρεμής επαναφορά, μοιραίο
// σφάλμα) το X και το Alt+F4 δεν έκλειναν πια το παράθυρο.
//
//   flutter test test/core/services/app_close_controller_test.dart

import 'package:call_logger/core/services/app_close_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppCloseController', () {
    test('ΤΟ ΣΦΑΛΜΑ: μετά την απόσυρση του χειριστή του κελύφους, το αίτημα '
        'κλεισίματος εξακολουθεί να τερματίζει', () {
      var shutdownRuns = 0;
      final controller = AppCloseController(
        runShutdown: () async => shutdownRuns++,
      );

      void shellHandler() {}
      controller.registerUiHandler(shellHandler);
      controller.unregisterUiHandler(shellHandler);

      controller.handleCloseRequest();

      expect(
        shutdownRuns,
        1,
        reason:
            'Χωρίς δανεισμένο χειριστή το παράθυρο έμενε παγιδευμένο: '
            'κανείς δεν απαντούσε στο X/Alt+F4.',
      );
    });

    test('με ζωντανό κέλυφος καλείται ο δανεισμένος χειριστής και ΟΧΙ το '
        'fallback', () {
      var shutdownRuns = 0;
      var handlerCalls = 0;
      final controller = AppCloseController(
        runShutdown: () async => shutdownRuns++,
      );

      controller.registerUiHandler(() => handlerCalls++);
      controller.handleCloseRequest();

      expect(handlerCalls, 1);
      expect(shutdownRuns, 0);
    });

    test('η απόσυρση αφορά μόνο τον ίδιο χειριστή — ο αντικαταστάτης '
        'επιβιώνει', () {
      var shutdownRuns = 0;
      var newHandlerCalls = 0;
      final controller = AppCloseController(
        runShutdown: () async => shutdownRuns++,
      );

      void oldHandler() {}
      controller.registerUiHandler(oldHandler);
      controller.registerUiHandler(() => newHandlerCalls++);
      // Το dispose του παλιού κελύφους τρέχει ΜΕΤΑ το initState του νέου.
      controller.unregisterUiHandler(oldHandler);

      controller.handleCloseRequest();

      expect(newHandlerCalls, 1);
      expect(shutdownRuns, 0);
      expect(controller.hasUiHandler, isTrue);
    });

    test('διπλό αίτημα κλεισίματος δεν τρέχει δύο φορές τον τερματισμό', () {
      var shutdownRuns = 0;
      final controller = AppCloseController(
        runShutdown: () async => shutdownRuns++,
      );

      controller.handleCloseRequest();
      controller.handleCloseRequest();

      expect(shutdownRuns, 1);
    });

    test('χωρίς εγκατάσταση δεν υπάρχει δανεισμένος χειριστής', () {
      final controller = AppCloseController(runShutdown: () async {});

      expect(controller.hasUiHandler, isFalse);
      expect(controller.isInstalled, isFalse);
    });
  });
}
