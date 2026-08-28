/// Η πολιτική «RPC εκτυπωτών» σε **αυτόν** τον υπολογιστή.
///
/// Τα Windows 11 ρωτούν τους απομακρυσμένους διακομιστές για εκτυπωτές μέσω
/// RPC over TCP· ο Windows Server 2003 ακούει μόνο σε named pipe. Το σύμπτωμα
/// είναι ο κωδικός 1753 στην απαρίθμηση και 1801 στο άνοιγμα του διακομιστή —
/// μετρημένο ζωντανά στον 192.168.13.82 στις 27/08/2026, μαζί με 16
/// συνδυασμούς παραμέτρων που κανένας δεν το παρακάμπτει.
///
/// Δύο τιμές μητρώου το λύνουν, και οι δύο απαραίτητες:
///  * `RpcUseNamedPipeProtocol` = 1 — χωρίς αυτό, σφάλμα 1753.
///  * `RpcAuthentication` = 2 — χωρίς αυτό, σφάλμα 5 (άρνηση πρόσβασης): σε
///    υπολογιστή τομέα η κλήση ταξιδεύει με την ταυτότητα του συνδεδεμένου
///    χρήστη αντί για εκείνη του λογαριασμού που ανοίγει η εφαρμογή.
///
/// **Η ανάγνωση δεν θέλει δικαιώματα· η εγγραφή θέλει.** Γι' αυτό η κατάσταση
/// φαίνεται πάντα, ενώ η εφαρμογή περνά μέσω ανύψωσης δικαιωμάτων (UAC).
///
/// **Δεν χρειάζεται επανεκκίνηση** — ούτε της υπηρεσίας ουράς ούτε του
/// υπολογιστή. Επιβεβαιωμένο: η αλλαγή πιάνει αμέσως.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _RegOpenKeyExNative =
    Int32 Function(
      IntPtr key,
      Pointer<Utf16> subKey,
      Uint32 options,
      Uint32 desired,
      Pointer<IntPtr> result,
    );
typedef _RegOpenKeyExDart =
    int Function(
      int key,
      Pointer<Utf16> subKey,
      int options,
      int desired,
      Pointer<IntPtr> result,
    );

typedef _RegQueryValueExNative =
    Int32 Function(
      IntPtr key,
      Pointer<Utf16> valueName,
      Pointer<Uint32> reserved,
      Pointer<Uint32> type,
      Pointer<Uint8> data,
      Pointer<Uint32> dataLen,
    );
typedef _RegQueryValueExDart =
    int Function(
      int key,
      Pointer<Utf16> valueName,
      Pointer<Uint32> reserved,
      Pointer<Uint32> type,
      Pointer<Uint8> data,
      Pointer<Uint32> dataLen,
    );

typedef _RegCloseKeyNative = Int32 Function(IntPtr key);
typedef _RegCloseKeyDart = int Function(int key);

typedef _ShellExecuteExNative = Int32 Function(Pointer<_ShellExecuteInfo> info);
typedef _ShellExecuteExDart = int Function(Pointer<_ShellExecuteInfo> info);

typedef _WaitForSingleObjectNative =
    Uint32 Function(IntPtr handle, Uint32 millis);
typedef _WaitForSingleObjectDart = int Function(int handle, int millis);

typedef _GetExitCodeProcessNative =
    Int32 Function(IntPtr process, Pointer<Uint32> exitCode);
typedef _GetExitCodeProcessDart = int Function(int process, Pointer<Uint32> ec);

typedef _CloseHandleNative = Int32 Function(IntPtr handle);
typedef _CloseHandleDart = int Function(int handle);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

/// `SHELLEXECUTEINFOW`. Η σειρά των πεδίων είναι συμβόλαιο των Windows — κάθε
/// μετακίνηση αλλάζει τη διάταξη στη μνήμη και η κλήση διαβάζει σκουπίδια.
final class _ShellExecuteInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  external Pointer<NativeType> hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  external Pointer<NativeType> hInstApp;
  external Pointer<NativeType> lpIDList;
  external Pointer<Utf16> lpClass;
  external Pointer<NativeType> hkeyClass;
  @Uint32()
  external int dwHotKey;
  external Pointer<NativeType> hIcon;
  @IntPtr()
  external int hProcess;
}

const int _hkeyLocalMachine = 0x80000002;
const int _keyRead = 0x20019;
const int _regDword = 4;

/// `ERROR_FILE_NOT_FOUND` — το κλειδί ή η τιμή δεν υπάρχει καθόλου.
const int _errorFileNotFound = 2;

/// `ERROR_CANCELLED` — ο χειριστής πάτησε «Όχι» στο παράθυρο των Windows.
const int _errorCancelled = 1223;

const int _seeMaskNoCloseProcess = 0x00000040;
const int _seeMaskNoAsync = 0x00000100;
const int _swHide = 0;

/// Πόσο περιμένουμε την εντολή αφού ο χειριστής απαντήσει στο παράθυρο των
/// Windows. Η ίδια η εγγραφή είναι στιγμιαία· ο χρόνος είναι για την απάντηση.
const int _elevationTimeoutMs = 120000;

/// Τι λέει το μητρώο για τις δύο τιμές της πολιτικής.
///
/// Κρατά και τις δύο ξεχωριστά — όχι μόνο «ενεργή ή όχι» — ώστε η οθόνη να
/// μπορεί να πει ποια από τις δύο λείπει. Η μισοπερασμένη ρύθμιση είναι
/// πραγματικό σενάριο: κάποιος περνά την πρώτη και σταματά στη δεύτερη.
class PrinterRpcPolicyState {
  const PrinterRpcPolicyState({
    required this.namedPipeOk,
    required this.authenticationOk,
    required this.readable,
  });

  /// Δεν διαβάστηκε το μητρώο — δεν ξέρουμε τίποτα.
  const PrinterRpcPolicyState.unreadable()
    : namedPipeOk = false,
      authenticationOk = false,
      readable = false;

  /// `RpcUseNamedPipeProtocol` = 1.
  final bool namedPipeOk;

  /// `RpcAuthentication` = 2.
  final bool authenticationOk;

  /// Ο έλεγχος ολοκληρώθηκε — αλλιώς οι δύο τιμές δεν σημαίνουν τίποτα.
  final bool readable;

  PrinterRpcPolicyStatus get status {
    if (!readable) return PrinterRpcPolicyStatus.unknown;
    if (namedPipeOk && authenticationOk) return PrinterRpcPolicyStatus.enabled;
    if (namedPipeOk || authenticationOk) return PrinterRpcPolicyStatus.partial;
    return PrinterRpcPolicyStatus.disabled;
  }

  /// Οι ρυθμίσεις που λείπουν, με τα ονόματα του Επεξεργαστή Πολιτικής.
  List<String> get missingLabels => [
    if (!namedPipeOk) 'RPC μέσω επώνυμων διοχετεύσεων',
    if (!authenticationOk) 'Ο έλεγχος ταυτότητας απενεργοποιήθηκε',
  ];

  /// Τι βλέπει ο χειριστής στην κάρτα — μία πρόταση κατάστασης και, όταν
  /// λείπει κάτι, τι σημαίνει αυτό στην πράξη.
  String get label => switch (status) {
    PrinterRpcPolicyStatus.enabled =>
      'Εκτυπωτές παλιών διακομιστών: πλήρης προβολή. Η ρύθμιση RPC είναι '
          'περασμένη και οι ουρές διαβάζονται κανονικά.',
    PrinterRpcPolicyStatus.partial =>
      'Εκτυπωτές παλιών διακομιστών: η ρύθμιση RPC είναι περασμένη μόνο κατά '
          'το ήμισυ — λείπει «${missingLabels.first}». Η προβολή θα μείνει '
          'περιορισμένη μέχρι να περαστεί και αυτή.',
    PrinterRpcPolicyStatus.disabled =>
      'Εκτυπωτές παλιών διακομιστών: περιορισμένη προβολή. Χωρίς τη ρύθμιση '
          'RPC βλέπεις ποιοι εκτυπωτές υπάρχουν, αλλά όχι τι περιμένει στις '
          'ουρές τους — και οι ενέργειες δεν είναι διαθέσιμες.',
    PrinterRpcPolicyStatus.unknown =>
      'Ρύθμιση RPC εκτυπωτών: δεν ήταν δυνατός ο έλεγχος σε αυτόν τον '
          'υπολογιστή.',
  };
}

/// Η κατάσταση της πολιτικής, όπως τη δείχνει η οθόνη.
enum PrinterRpcPolicyStatus {
  /// Και οι δύο τιμές περασμένες — τίποτα να κάνει ο χειριστής.
  enabled,

  /// Περασμένη η μία από τις δύο· η προβολή μένει περιορισμένη.
  partial,

  /// Καμία από τις δύο.
  disabled,

  /// Δεν διαβάστηκε το μητρώο.
  unknown,
}

extension PrinterRpcPolicyStatusText on PrinterRpcPolicyStatus {
  bool get isProblem =>
      this == PrinterRpcPolicyStatus.disabled ||
      this == PrinterRpcPolicyStatus.partial;
}

/// Το αποτέλεσμα της εφαρμογής — τρεις εκβάσεις που θέλουν διαφορετικά λόγια.
enum PrinterRpcPolicyApplyOutcome {
  /// Η ρύθμιση πέρασε.
  applied,

  /// Ο χειριστής αρνήθηκε την ανύψωση δικαιωμάτων.
  cancelled,

  /// Κάτι άλλο πήγε στραβά — το [PrinterRpcPolicyApplyResult.detail] λέει τι.
  failed,
}

class PrinterRpcPolicyApplyResult {
  const PrinterRpcPolicyApplyResult(this.outcome, [this.detail]);

  final PrinterRpcPolicyApplyOutcome outcome;

  /// Τεχνική λεπτομέρεια της αποτυχίας — κενή όταν δεν υπάρχει.
  final String? detail;
}

abstract final class PrinterRpcPolicy {
  PrinterRpcPolicy._();

  /// Το κλειδί της πολιτικής, κάτω από `HKEY_LOCAL_MACHINE`.
  static const String registryPath =
      r'SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC';

  static const String namedPipeValueName = 'RpcUseNamedPipeProtocol';
  static const String authenticationValueName = 'RpcAuthentication';

  /// Οι τιμές που θέλουμε. Το 2 στον έλεγχο ταυτότητας σημαίνει
  /// «απενεργοποιημένος» — δεν είναι αυθαίρετος αριθμός.
  static const int namedPipeWanted = 1;
  static const int authenticationWanted = 2;

  /// Η εντολή που περνά τις δύο τιμές, ως ένα βήμα.
  ///
  /// Ένα `cmd.exe` και όχι δύο κλήσεις `reg.exe`: αλλιώς ο χειριστής θα έβλεπε
  /// **δύο** παράθυρα ανύψωσης για μία ρύθμιση, και η άρνηση στο δεύτερο θα
  /// άφηνε τον υπολογιστή μισοπερασμένο.
  static String get elevationArguments {
    final key = 'HKLM\\$registryPath';
    return '/c reg add "$key" /v $namedPipeValueName /t REG_DWORD '
        '/d $namedPipeWanted /f && reg add "$key" /v $authenticationValueName '
        '/t REG_DWORD /d $authenticationWanted /f';
  }

  /// Η εντολή που ξηλώνει τη ρύθμιση και επιστρέφει στη συμπεριφορά που έχουν
  /// τα Windows 11 από μόνα τους.
  ///
  /// Σβήνει **μόνο τις δύο δικές μας τιμές**, όχι ολόκληρο το κλειδί: εκεί
  /// μέσα μπορεί να κάθονται κι άλλες ρυθμίσεις εκτυπώσεων που δεν βάλαμε
  /// εμείς και δεν μας ανήκει να τις πετάξουμε.
  ///
  /// Οι εντολές αλυσιδώνονται με `&` και όχι με `&&`, και κλείνουν με
  /// `exit 0`: η μία από τις δύο τιμές μπορεί κάλλιστα να λείπει ήδη, και η
  /// «αποτυχία» της διαγραφής της δεν είναι αποτυχία της δουλειάς. Το αν
  /// έφυγαν το κρίνει το μητρώο μετά, όχι ο κωδικός εξόδου.
  static String get restoreDefaultsArguments {
    final key = 'HKLM\\$registryPath';
    return '/c reg delete "$key" /v $namedPipeValueName /f '
        '& reg delete "$key" /v $authenticationValueName /f & exit 0';
  }

  /// Η κατάσταση της πολιτικής σε αυτόν τον υπολογιστή.
  static Future<PrinterRpcPolicyState> current() async {
    if (!Platform.isWindows) return const PrinterRpcPolicyState.unreadable();
    return _read();
  }

  /// Περνά τη ρύθμιση, ζητώντας ανύψωση δικαιωμάτων από τα Windows.
  static Future<PrinterRpcPolicyApplyResult> applyElevated() {
    return _elevate(
      elevationArguments,
      succeededWhen: (state) => state.status == PrinterRpcPolicyStatus.enabled,
      failureLead: 'Η ρύθμιση δεν πέρασε.',
    );
  }

  /// Ξηλώνει τη ρύθμιση και επιστρέφει τις προεπιλογές των Windows 11.
  static Future<PrinterRpcPolicyApplyResult> restoreDefaultsElevated() {
    return _elevate(
      restoreDefaultsArguments,
      succeededWhen: (state) => state.status == PrinterRpcPolicyStatus.disabled,
      failureLead: 'Η επαναφορά δεν ολοκληρώθηκε.',
    );
  }

  /// Τρέχει μια εντολή με ανύψωση δικαιωμάτων και **επαληθεύει το αποτέλεσμα
  /// στο μητρώο**.
  ///
  /// Η επαλήθευση δεν είναι πολυτέλεια: ο κωδικός εξόδου λέει μόνο ότι η
  /// εντολή δεν παραπονέθηκε. Αυτό που ενδιαφέρει τον χειριστή είναι τι λέει
  /// τώρα ο υπολογιστής του — και αυτό το ξέρει μόνο το μητρώο.
  ///
  /// Η ίδια η κλήση τρέχει σε ξεχωριστό isolate: η αναμονή της απάντησης στο
  /// παράθυρο των Windows είναι μπλοκαριστική και θα πάγωνε την οθόνη.
  static Future<PrinterRpcPolicyApplyResult> _elevate(
    String arguments, {
    required bool Function(PrinterRpcPolicyState) succeededWhen,
    required String failureLead,
  }) async {
    if (!Platform.isWindows) {
      return PrinterRpcPolicyApplyResult(
        PrinterRpcPolicyApplyOutcome.failed,
        '$failureLead Η ρύθμιση αφορά μόνο Windows.',
      );
    }

    final launch = await Isolate.run(() => _runElevated(arguments));
    if (launch.outcome == PrinterRpcPolicyApplyOutcome.cancelled) {
      return launch;
    }

    final after = await current();
    if (succeededWhen(after)) {
      return const PrinterRpcPolicyApplyResult(
        PrinterRpcPolicyApplyOutcome.applied,
      );
    }
    return PrinterRpcPolicyApplyResult(
      PrinterRpcPolicyApplyOutcome.failed,
      '$failureLead ${launch.detail ?? 'Το μητρώο δεν άλλαξε.'}',
    );
  }

  static PrinterRpcPolicyState _read() {
    try {
      final advapi = DynamicLibrary.open('advapi32.dll');
      final openKey = advapi
          .lookupFunction<_RegOpenKeyExNative, _RegOpenKeyExDart>(
            'RegOpenKeyExW',
          );
      final queryValue = advapi
          .lookupFunction<_RegQueryValueExNative, _RegQueryValueExDart>(
            'RegQueryValueExW',
          );
      final closeKey = advapi
          .lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

      final pathPtr = registryPath.toNativeUtf16();
      final keyPtr = calloc<IntPtr>();
      try {
        final opened = openKey(_hkeyLocalMachine, pathPtr, 0, _keyRead, keyPtr);
        if (opened == _errorFileNotFound) {
          // Το κλειδί δεν υπάρχει: καμία ρύθμιση περασμένη. Είναι απάντηση,
          // όχι αποτυχία ανάγνωσης — γι' αυτό δεν γυρίζει «άγνωστο».
          return const PrinterRpcPolicyState(
            namedPipeOk: false,
            authenticationOk: false,
            readable: true,
          );
        }
        if (opened != 0) return const PrinterRpcPolicyState.unreadable();

        final key = keyPtr.value;
        try {
          return PrinterRpcPolicyState(
            namedPipeOk:
                _readDword(queryValue, key, namedPipeValueName) ==
                namedPipeWanted,
            authenticationOk:
                _readDword(queryValue, key, authenticationValueName) ==
                authenticationWanted,
            readable: true,
          );
        } finally {
          closeKey(key);
        }
      } finally {
        calloc.free(pathPtr);
        calloc.free(keyPtr);
      }
    } catch (_) {
      return const PrinterRpcPolicyState.unreadable();
    }
  }

  /// Η τιμή ως ακέραιος, ή `null` όταν λείπει ή δεν είναι αριθμός.
  static int? _readDword(
    _RegQueryValueExDart queryValue,
    int key,
    String valueName,
  ) {
    final namePtr = valueName.toNativeUtf16();
    final typePtr = calloc<Uint32>();
    final dataPtr = calloc<Uint8>(4);
    final lenPtr = calloc<Uint32>()..value = 4;
    try {
      final result = queryValue(
        key,
        namePtr,
        nullptr,
        typePtr,
        dataPtr,
        lenPtr,
      );
      if (result != 0) return null;
      if (typePtr.value != _regDword) return null;
      return dataPtr.cast<Uint32>().value;
    } finally {
      calloc.free(namePtr);
      calloc.free(typePtr);
      calloc.free(dataPtr);
      calloc.free(lenPtr);
    }
  }

  static PrinterRpcPolicyApplyResult _runElevated(String arguments) {
    final shell = DynamicLibrary.open('shell32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final shellExecuteEx = shell
        .lookupFunction<_ShellExecuteExNative, _ShellExecuteExDart>(
          'ShellExecuteExW',
        );
    final waitForSingleObject = kernel
        .lookupFunction<_WaitForSingleObjectNative, _WaitForSingleObjectDart>(
          'WaitForSingleObject',
        );
    final getExitCode = kernel
        .lookupFunction<_GetExitCodeProcessNative, _GetExitCodeProcessDart>(
          'GetExitCodeProcess',
        );
    final closeHandle = kernel
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    final getLastError = kernel
        .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

    final infoPtr = calloc<_ShellExecuteInfo>();
    final verbPtr = 'runas'.toNativeUtf16();
    final filePtr = 'cmd.exe'.toNativeUtf16();
    final argsPtr = arguments.toNativeUtf16();
    final exitPtr = calloc<Uint32>();
    try {
      final info = infoPtr.ref;
      info.cbSize = sizeOf<_ShellExecuteInfo>();
      info.fMask = _seeMaskNoCloseProcess | _seeMaskNoAsync;
      info.lpVerb = verbPtr;
      info.lpFile = filePtr;
      info.lpParameters = argsPtr;
      info.nShow = _swHide;

      if (shellExecuteEx(infoPtr) == 0) {
        final code = getLastError();
        if (code == _errorCancelled) {
          return const PrinterRpcPolicyApplyResult(
            PrinterRpcPolicyApplyOutcome.cancelled,
          );
        }
        return PrinterRpcPolicyApplyResult(
          PrinterRpcPolicyApplyOutcome.failed,
          'Κωδικός Windows $code.',
        );
      }

      final process = infoPtr.ref.hProcess;
      if (process == 0) {
        // Χωρίς χειριστήριο δεν ξέρουμε αν πέτυχε — και το «μάλλον πέτυχε»
        // είναι χειρότερο από το «δεν ξέρω»: ο επόμενος έλεγχος θα το πει.
        return const PrinterRpcPolicyApplyResult(
          PrinterRpcPolicyApplyOutcome.failed,
          'Η εντολή ξεκίνησε αλλά δεν ήταν δυνατή η παρακολούθησή της.',
        );
      }
      try {
        waitForSingleObject(process, _elevationTimeoutMs);
        if (getExitCode(process, exitPtr) == 0) {
          return const PrinterRpcPolicyApplyResult(
            PrinterRpcPolicyApplyOutcome.failed,
            'Δεν διαβάστηκε το αποτέλεσμα της εντολής.',
          );
        }
        final exitCode = exitPtr.value;
        if (exitCode == 0) {
          return const PrinterRpcPolicyApplyResult(
            PrinterRpcPolicyApplyOutcome.applied,
          );
        }
        return PrinterRpcPolicyApplyResult(
          PrinterRpcPolicyApplyOutcome.failed,
          'Η εντολή τερμάτισε με κωδικό $exitCode.',
        );
      } finally {
        closeHandle(process);
      }
    } catch (e) {
      return PrinterRpcPolicyApplyResult(
        PrinterRpcPolicyApplyOutcome.failed,
        '$e',
      );
    } finally {
      calloc.free(infoPtr);
      calloc.free(verbPtr);
      calloc.free(filePtr);
      calloc.free(argsPtr);
      calloc.free(exitPtr);
    }
  }
}
