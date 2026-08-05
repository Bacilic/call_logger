import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

/// Εκκίνηση του `.cmd` updater σε Windows, σε ΜΙΑ δική του κονσόλα.
///
/// Δύο αποδεδειγμένες παγίδες που ΑΠΟΦΕΥΓΟΝΤΑΙ εδώ:
///
/// 1. **Quoting του cmd:** χωρίς `/s`, ο `cmd /c` διατηρεί τα εισαγωγικά μόνο
///    όταν η γραμμή μετά το `/c` έχει ΑΚΡΙΒΩΣ δύο. Γι' αυτό σε εισαγωγικά
///    μπαίνει ΜΟΝΟ η διαδρομή του script (που μπορεί να έχει κενά, π.χ.
///    `Documents\Call Logger`)· τα ορίσματα είναι σκέτο PID χωρίς κενά και
///    περνούν αχώριστα — το [buildCommandLine] το επιβάλλει.
/// 2. **Καταιγίδα παραθύρων:** το `Process.start(detached)` του Dart περνά τη
///    σημαία DETACHED_PROCESS, οπότε το cmd.exe τρέχει ΧΩΡΙΣ κονσόλα. Batch
///    χωρίς κονσόλα σημαίνει ότι ΚΑΘΕ παιδί του (`tasklist`, `timeout`,
///    `robocopy`) ανοίγει δικό του νέο παράθυρο — ο βρόχος αναμονής άνοιγε
///    3 παράθυρα το δευτερόλεπτο («δαιμονισμένο pc»). Η λύση είναι η αντίθετη
///    σημαία: μία κονσόλα για το cmd.exe, που την κληρονομούν ΟΛΑ τα παιδιά.
///
/// Η εκκίνηση γίνεται με CreateProcess (FFI) επειδή το Dart δεν προσφέρει
/// έλεγχο στις σημαίες δημιουργίας. Η νέα διεργασία είναι ανεξάρτητη από τη
/// ζωή της εφαρμογής (τα Windows δεν σκοτώνουν παιδιά όταν κλείνει ο γονιός),
/// άρα ο updater επιβιώνει του `exit(0)` που ακολουθεί.
class UpdateCmdLauncher {
  UpdateCmdLauncher._();

  /// Σημαίες δημιουργίας διεργασίας — ΠΟΤΕ DETACHED_PROCESS (βλ. σχόλιο
  /// κλάσης). Ορατή κονσόλα με την πρόοδο της ενημέρωσης, ή αόρατη (τεστ).
  static PROCESS_CREATION_FLAGS creationFlags({required bool visibleConsole}) {
    return visibleConsole ? CREATE_NEW_CONSOLE : CREATE_NO_WINDOW;
  }

  /// Πλήρης γραμμή εντολών για το CreateProcess.
  ///
  /// Μετά το `/c` υπάρχει ΑΚΡΙΒΩΣ ένα ζεύγος εισαγωγικών (η διαδρομή του
  /// script)· ορίσματα με κενά ή εισαγωγικά θα το χαλούσαν και απορρίπτονται.
  static String buildCommandLine(
    String cmdExePath,
    String scriptPath,
    List<String> scriptArgs,
  ) {
    for (final arg in scriptArgs) {
      if (arg.contains(' ') || arg.contains('"')) {
        throw ArgumentError.value(
          arg,
          'scriptArgs',
          'Τα ορίσματα του updater δεν επιτρέπεται να έχουν κενά ή '
              'εισαγωγικά — θα έσπαγαν τον κανόνα των δύο εισαγωγικών του cmd',
        );
      }
    }
    final args = scriptArgs.isEmpty ? '' : ' ${scriptArgs.join(' ')}';
    return '"$cmdExePath" /d /c "$scriptPath"$args';
  }

  /// Εκκινεί το [scriptPath] μέσω `cmd.exe /d /c` σε δική του κονσόλα,
  /// ανεξάρτητο από τη ζωή της εφαρμογής.
  static Future<void> launch({
    required String scriptPath,
    required List<String> scriptArgs,
    String? workingDirectory,
    bool visibleConsole = true,
  }) async {
    final cmdExe = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'cmd.exe',
    );
    final commandLine = buildCommandLine(cmdExe, scriptPath, scriptArgs);

    final appName = cmdExe.toPcwstr(allocator: calloc);
    // Το CreateProcessW μπορεί να τροποποιήσει το buffer της γραμμής εντολών —
    // γι' αυτό εγγράψιμο PWSTR και όχι PCWSTR.
    final cmdLine = commandLine.toPwstr(allocator: calloc);
    final cwd = workingDirectory?.toPcwstr(allocator: calloc);
    final startupInfo = calloc<STARTUPINFO>();
    final processInfo = calloc<PROCESS_INFORMATION>();
    try {
      startupInfo.ref.cb = sizeOf<STARTUPINFO>();
      final result = CreateProcess(
        appName,
        cmdLine,
        null,
        null,
        false,
        creationFlags(visibleConsole: visibleConsole),
        null,
        cwd,
        startupInfo,
        processInfo,
      );
      if (!result.value) {
        throw ProcessException(
          'cmd.exe',
          ['/d', '/c', scriptPath, ...scriptArgs],
          'CreateProcess απέτυχε (κωδικός Windows ${result.error})',
        );
      }
      // Ο updater ζει ανεξάρτητα — τα handles δεν χρειάζονται σε εμάς.
      CloseHandle(processInfo.ref.hProcess);
      CloseHandle(processInfo.ref.hThread);
    } finally {
      calloc.free(appName);
      calloc.free(cmdLine);
      if (cwd != null) calloc.free(cwd);
      calloc.free(startupInfo);
      calloc.free(processInfo);
    }
  }
}
