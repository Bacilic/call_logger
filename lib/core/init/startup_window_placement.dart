import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../services/desktop_window_service.dart';
import '../../features/calls/screens/widgets/call_header_form.dart';

/// Ελάχιστο πλάτος εφαρμογής: γραμμή πεδίων + padding Κλήσεων (16*2) +
/// συμπυγμένο NavigationRail + περιθώριο.
const double _kCallsScreenPaddingH = 32;
const double _kNavigationRailMinWidth = 80;
const double _kMinWindowWidthMargin = 20;

double get kMinWindowWidth =>
    kCallHeaderRowMinWidth +
    _kCallsScreenPaddingH +
    _kNavigationRailMinWidth +
    _kMinWindowWidthMargin;

const double kMinWindowHeight = 640;

/// Πόσο μικρότερο από το ελάχιστο της εφαρμογής είναι το παράθυρο εκκίνησης.
///
/// Η οθόνη εκκίνησης δεν έχει καμία σχέση με το μέγεθος που δουλεύει ο χρήστης:
/// είναι μια κάρτα που εμφανίζεται, λέει τι κάνει και φεύγει. Δένεται στο
/// **ελάχιστο** μέγεθος και όχι στο αποθηκευμένο, ώστε να είναι ίδια κάθε φορά.
const double kSplashWindowFactor = 0.75;

/// Το παράθυρο σε δύο φάσεις: πρώτα η κάρτα της εκκίνησης, μετά η εφαρμογή.
class StartupWindowPlacement {
  const StartupWindowPlacement._();

  /// Φάση 1 — η οθόνη εκκίνησης: μικρό, κεντραρισμένο παράθυρο.
  ///
  /// Το ελάχιστο μέγεθος **δεν** ορίζεται εδώ επίτηδες. Το `setMinimumSize`
  /// είναι φράγμα που το λειτουργικό επιβάλλει αμέσως: αν έμπαινε τώρα, το
  /// παράθυρο δεν θα μπορούσε να γίνει μικρότερο από αυτό και η κάρτα θα
  /// άνοιγε σε μέγεθος εφαρμογής. Μπαίνει στη φάση 2, όπου αρχίζει να ισχύει.
  static Future<void> applySplashWindow({
    required WindowManager windowManager,
    required double screenWidth,
    required double screenHeight,
  }) async {
    await windowManager.setSize(
      splashWindowSize(screenWidth: screenWidth, screenHeight: screenHeight),
    );
    await windowManager.center();
  }

  /// Οι διαστάσεις της κάρτας εκκίνησης, περιορισμένες στην οθόνη.
  ///
  /// Ο περιορισμός δεν είναι θεωρητικός: σε παλιό μηχάνημα του νοσοκομείου με
  /// οθόνη 1024x768 η κάρτα χωρά άνετα, αλλά σε προβολέα ή απομακρυσμένη
  /// σύνδεση χαμηλής ανάλυσης ένα παράθυρο μεγαλύτερο από την οθόνη δεν
  /// κεντράρεται — φεύγει εκτός.
  static Size splashWindowSize({
    required double screenWidth,
    required double screenHeight,
  }) {
    return Size(
      math.min(screenWidth, kMinWindowWidth * kSplashWindowFactor),
      math.min(screenHeight, kMinWindowHeight * kSplashWindowFactor),
    );
  }

  /// Φάση 2 — η εφαρμογή: το ελάχιστο μέγεθος αρχίζει να ισχύει και το
  /// παράθυρο επανέρχεται στις αποθηκευμένες διαστάσεις και θέση.
  static Future<void> restoreApplicationWindow({
    WindowManager? windowManager,
    DesktopWindowService? windowService,
  }) async {
    final wm = windowManager ?? WindowManager.instance;
    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    final screenWidth = display.size.width;
    final screenHeight = display.size.height;
    final minW = math.min(kMinWindowWidth, screenWidth);
    final minH = math.min(kMinWindowHeight, screenHeight);

    await wm.setMinimumSize(Size(minW, minH));
    await (windowService ?? DesktopWindowService()).applyStartupPlacement(
      windowManager: wm,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      minWidth: minW,
      minHeight: minH,
    );
  }
}
