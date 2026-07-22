import 'dart:io';

/// Ασφαλής εκκίνηση `.cmd` updater σε Windows (διαδρομές με κενά).
///
/// Δύο αποδεδειγμένα λάθη που ΑΠΟΦΕΥΓΟΝΤΑΙ εδώ:
/// 1. ΔΕΝ φτιάχνουμε ένα προ-quoted string τύπου `"script" arg "path"` για
///    το `cmd /c`: το [Process.start] των Windows ξανα-escape-άρει τα `"` ως
///    `\"` και το `cmd.exe` δεν τα αναγνωρίζει (η εντολή σπάει, η εφαρμογή
///    κλείνει χωρίς εγκατάσταση).
/// 2. ΔΕΝ περνάμε πολλές διαδρομές με κενά ως ξεχωριστά ορίσματα: χωρίς `/s`
///    ο `cmd /c` κρατά εισαγωγικά μόνο όταν η γραμμή έχει ΑΚΡΙΒΩΣ δύο· με
///    περισσότερα quoted ορίσματα κόβει λάθος και σπάει στο πρώτο κενό.
///
/// Λύση: το script δέχεται ΜΟΝΟ το PID ως όρισμα (σκέτος αριθμός, χωρίς κενά)
/// και υπολογίζει μόνο του τις διαδρομές από το `%~dp0`. Έτσι η μόνη τιμή με
/// κενά είναι η διαδρομή του ίδιου του script, που το Dart την περικλείει σε
/// ένα ζεύγος εισαγωγικών — ακριβώς δύο — και ο `cmd /c` τη διατηρεί.
class UpdateCmdLauncher {
  UpdateCmdLauncher._();

  /// Εκκινεί [scriptPath] αποσπασμένα μέσω `cmd.exe /d /c`.
  static Future<void> launchDetached({
    required String scriptPath,
    required List<String> scriptArgs,
    String? workingDirectory,
  }) async {
    await Process.start(
      'cmd.exe',
      buildCmdExeArguments(scriptPath, scriptArgs),
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }

  /// Ορίσματα για `Process.start('cmd.exe', ...)`.
  ///
  /// Επιστρέφει `['/d', '/c', <script>, <args...>]` με τα ορίσματα ΞΕΧΩΡΙΣΤΑ,
  /// ώστε το Dart να προσθέσει σωστά εισαγωγικά όπου χρειάζεται. Χωρίς `/s`
  /// και χωρίς χειροποίητα εισαγωγικά (βλ. σχόλιο κλάσης).
  static List<String> buildCmdExeArguments(
    String scriptPath,
    List<String> scriptArgs,
  ) {
    return ['/d', '/c', scriptPath, ...scriptArgs];
  }
}
