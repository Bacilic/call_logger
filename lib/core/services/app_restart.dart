import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import '../config/app_config.dart';
import 'app_close_controller.dart';

/// Το όρισμα που λέει στη νέα εφαρμογή «περίμενε πρώτα να κλείσει η παλιά».
const String afterExitOfFlag = '--after-exit-of=';

/// Τα ορίσματα της νέας εφαρμογής: ό,τι είχε η τρέχουσα (π.χ. το προφίλ) και
/// η οδηγία αναμονής για **αυτή** τη διεργασία.
///
/// Η οδηγία μιας προηγούμενης επανεκκίνησης δεν ξαναπερνά: αφορά διεργασία
/// που έχει ήδη τελειώσει.
List<String> relaunchArguments(
  List<String> launchArguments, {
  required int processId,
}) {
  return [
    for (final arg in launchArguments)
      if (!arg.startsWith(afterExitOfFlag)) arg,
    '$afterExitOfFlag$processId',
  ];
}

/// Η «Επανεκκίνηση εφαρμογής»: η νέα ξεκινά με οδηγία να περιμένει, και η
/// τρέχουσα κλείνει με τον **κανονικό** τρόπο, όπως με το «Χ».
///
/// Μέχρι 17/10/2026 η επανεκκίνηση τερμάτιζε επιτόπου: το σημάδι ζωής έμενε
/// πίσω, η νέα το έβρισκε ζωντανό και το κατέγραφε ως «ΑΠΟΤΟΜΟ ΤΕΛΟΣ», και ο
/// χρήστης φαινόταν συνδεδεμένος ως τη λήξη.
///
/// Πετά αν η νέα εφαρμογή δεν ξεκινήσει — τότε η τρέχουσα **δεν** κλείνει.
/// Αλλιώς δεν επιστρέφει ποτέ: το κλείσιμο τελειώνει με το τέλος της
/// διεργασίας.
Future<void> restartApplication({AppCloseController? controller}) async {
  await Process.start(
    Platform.resolvedExecutable,
    relaunchArguments(AppConfig.launchArguments, processId: pid),
    mode: ProcessStartMode.detached,
  );
  (controller ?? appCloseController).handleCloseRequest();
  return Completer<void>().future;
}

/// Περιμένει να τερματιστεί η διεργασία [processId] — έως [timeout].
///
/// Επιστρέφει `false` όταν πέρασε το όριο και η διεργασία ζει ακόμη: η
/// εκκίνηση συνεχίζει, ώστε ο χρήστης να μη μείνει ποτέ χωρίς εφαρμογή.
Future<bool> waitUntilProcessGone(
  int processId, {
  bool Function(int processId) isAlive = isProcessAlive,
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 200),
  Future<void> Function(Duration duration) delay = Future<void>.delayed,
}) async {
  var waited = Duration.zero;
  while (isAlive(processId)) {
    if (waited >= timeout) return false;
    await delay(pollInterval);
    waited += pollInterval;
  }
  return true;
}

const int _synchronize = 0x00100000;
const int _waitTimeout = 0x00000102;

typedef _OpenProcessNative = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _WaitNative = Uint32 Function(IntPtr, Uint32);
typedef _WaitDart = int Function(int, int);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

/// Ζει ακόμη η διεργασία; Εκτός Windows, ή αν η ερώτηση αποτύχει, απαντά
/// «όχι» — η αναμονή δεν πρέπει ποτέ να κρατήσει την εκκίνηση στα τυφλά.
bool isProcessAlive(int processId) {
  if (!Platform.isWindows) return false;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final openProcess = kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    final wait = kernel32.lookupFunction<_WaitNative, _WaitDart>(
      'WaitForSingleObject',
    );
    final closeHandle = kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    final handle = openProcess(_synchronize, 0, processId);
    if (handle == 0) return false;
    try {
      return wait(handle, 0) == _waitTimeout;
    } finally {
      closeHandle(handle);
    }
  } catch (_) {
    return false;
  }
}
