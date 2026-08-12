import 'package:call_logger/core/init/startup_window_placement.dart';
import 'package:flutter_test/flutter_test.dart';

/// Οι διαστάσεις της κάρτας εκκίνησης δένονται στο **ελάχιστο** μέγεθος της
/// εφαρμογής και όχι στο αποθηκευμένο: η κάρτα είναι ίδια κάθε φορά, ό,τι κι αν
/// έχει κάνει ο χρήστης με το παράθυρό του.
void main() {
  group('Διαστάσεις κάρτας εκκίνησης', () {
    test('είναι 75% του ελάχιστου μεγέθους της εφαρμογής', () {
      final size = StartupWindowPlacement.splashWindowSize(
        screenWidth: 1920,
        screenHeight: 1080,
      );

      expect(kSplashWindowFactor, 0.75);
      expect(size.width, kMinWindowWidth * 0.75);
      expect(size.height, 480);
    });

    test('δεν εξαρτώνται από το μέγεθος της οθόνης όταν χωρούν', () {
      final onBig = StartupWindowPlacement.splashWindowSize(
        screenWidth: 3840,
        screenHeight: 2160,
      );
      final onSmall = StartupWindowPlacement.splashWindowSize(
        screenWidth: 1280,
        screenHeight: 1024,
      );

      expect(onBig, onSmall);
    });

    test('περιορίζονται σε οθόνη μικρότερη από την κάρτα', () {
      final size = StartupWindowPlacement.splashWindowSize(
        screenWidth: 640,
        screenHeight: 400,
      );

      expect(size.width, 640);
      expect(size.height, 400);
    });

    test('μένουν μικρότερες από το ελάχιστο μέγεθος της εφαρμογής', () {
      final size = StartupWindowPlacement.splashWindowSize(
        screenWidth: 1920,
        screenHeight: 1080,
      );

      expect(size.width, lessThan(kMinWindowWidth));
      expect(size.height, lessThan(kMinWindowHeight));
    });
  });
}
