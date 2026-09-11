/// Κλήσεις προς τα Windows API για εκτυπωτές, υπηρεσίες και επανεκκίνηση.
///
/// Ισχύει ό,τι και για τις συνεδρίες: η ταυτότητα ακολουθεί την ανοιχτή
/// συνεδρία SMB, οπότε κάθε κλήση εδώ προϋποθέτει ότι έχει προηγηθεί
/// [WindowsSessionFfi.connectIpcShare] με στοιχεία διαχειριστή.
///
/// Όλες οι συναρτήσεις **μπλοκάρουν** και καλούνται μέσα από `Isolate.run`.
library;

import 'dart:ffi';
import 'dart:io' show sleep;

import 'package:ffi/ffi.dart';

import 'server_printer_messages.dart';

// --- Δομές -----------------------------------------------------------------

/// `PRINTER_INFO_2W`. Δηλώνονται **όλα** τα πεδία, ακόμη και όσα δεν
/// διαβάζουμε: το μέγεθος της δομής ορίζει το βήμα του πίνακα, και ένα πεδίο
/// που λείπει θα διάβαζε μετατοπισμένα σκουπίδια αντί να αποτύχει.
final class _PrinterInfo2 extends Struct {
  external Pointer<Utf16> pServerName;
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pShareName;
  external Pointer<Utf16> pPortName;
  external Pointer<Utf16> pDriverName;
  external Pointer<Utf16> pComment;
  external Pointer<Utf16> pLocation;
  external Pointer<NativeType> pDevMode;
  external Pointer<Utf16> pSepFile;
  external Pointer<Utf16> pPrintProcessor;
  external Pointer<Utf16> pDatatype;
  external Pointer<Utf16> pParameters;
  external Pointer<NativeType> pSecurityDescriptor;
  @Uint32()
  external int attributes;
  @Uint32()
  external int priority;
  @Uint32()
  external int defaultPriority;
  @Uint32()
  external int startTime;
  @Uint32()
  external int untilTime;
  @Uint32()
  external int status;
  @Uint32()
  external int cJobs;
  @Uint32()
  external int averagePpm;
}

/// `JOB_INFO_1W` — το απλούστερο επίπεδο που δίνει έγγραφο, χρήστη και σελίδες.
final class _JobInfo1 extends Struct {
  @Uint32()
  external int jobId;
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pMachineName;
  external Pointer<Utf16> pUserName;
  external Pointer<Utf16> pDocument;
  external Pointer<Utf16> pDatatype;
  external Pointer<Utf16> pStatus;
  @Uint32()
  external int status;
  @Uint32()
  external int priority;
  @Uint32()
  external int position;
  @Uint32()
  external int totalPages;
  @Uint32()
  external int pagesPrinted;
  // SYSTEMTIME Submitted — δηλώνεται για το σωστό μέγεθος της δομής.
  @Uint16()
  external int submittedYear;
  @Uint16()
  external int submittedMonth;
  @Uint16()
  external int submittedDayOfWeek;
  @Uint16()
  external int submittedDay;
  @Uint16()
  external int submittedHour;
  @Uint16()
  external int submittedMinute;
  @Uint16()
  external int submittedSecond;
  @Uint16()
  external int submittedMilliseconds;
}

final class _ServiceStatus extends Struct {
  @Uint32()
  external int serviceType;
  @Uint32()
  external int currentState;
  @Uint32()
  external int controlsAccepted;
  @Uint32()
  external int win32ExitCode;
  @Uint32()
  external int serviceSpecificExitCode;
  @Uint32()
  external int checkPoint;
  @Uint32()
  external int waitHint;
}

// --- Υπογραφές: εκτυπωτές (winspool.drv) -----------------------------------

typedef _EnumPrintersNative =
    Int32 Function(
      Uint32 flags,
      Pointer<Utf16> name,
      Uint32 level,
      Pointer<Uint8> buffer,
      Uint32 bufferSize,
      Pointer<Uint32> needed,
      Pointer<Uint32> returned,
    );
typedef _EnumPrintersDart =
    int Function(
      int flags,
      Pointer<Utf16> name,
      int level,
      Pointer<Uint8> buffer,
      int bufferSize,
      Pointer<Uint32> needed,
      Pointer<Uint32> returned,
    );

typedef _OpenPrinterNative =
    Int32 Function(
      Pointer<Utf16> printerName,
      Pointer<IntPtr> handle,
      Pointer<NativeType> defaults,
    );
typedef _OpenPrinterDart =
    int Function(
      Pointer<Utf16> printerName,
      Pointer<IntPtr> handle,
      Pointer<NativeType> defaults,
    );

typedef _ClosePrinterNative = Int32 Function(IntPtr handle);
typedef _ClosePrinterDart = int Function(int handle);

typedef _EnumJobsNative =
    Int32 Function(
      IntPtr printer,
      Uint32 firstJob,
      Uint32 noJobs,
      Uint32 level,
      Pointer<Uint8> buffer,
      Uint32 bufferSize,
      Pointer<Uint32> needed,
      Pointer<Uint32> returned,
    );
typedef _EnumJobsDart =
    int Function(
      int printer,
      int firstJob,
      int noJobs,
      int level,
      Pointer<Uint8> buffer,
      int bufferSize,
      Pointer<Uint32> needed,
      Pointer<Uint32> returned,
    );

typedef _SetJobNative =
    Int32 Function(
      IntPtr printer,
      Uint32 jobId,
      Uint32 level,
      Pointer<NativeType> job,
      Uint32 command,
    );
typedef _SetJobDart =
    int Function(
      int printer,
      int jobId,
      int level,
      Pointer<NativeType> job,
      int command,
    );

typedef _DeletePrinterNative = Int32 Function(IntPtr printer);
typedef _DeletePrinterDart = int Function(int printer);

typedef _SetPrinterNative =
    Int32 Function(
      IntPtr printer,
      Uint32 level,
      Pointer<NativeType> printerInfo,
      Uint32 command,
    );
typedef _SetPrinterDart =
    int Function(
      int printer,
      int level,
      Pointer<NativeType> printerInfo,
      int command,
    );

// --- Υπογραφές: υπηρεσίες & τερματισμός (advapi32) -------------------------

typedef _OpenScManagerNative =
    IntPtr Function(
      Pointer<Utf16> machineName,
      Pointer<Utf16> databaseName,
      Uint32 desiredAccess,
    );
typedef _OpenScManagerDart =
    int Function(
      Pointer<Utf16> machineName,
      Pointer<Utf16> databaseName,
      int desiredAccess,
    );

typedef _OpenServiceNative =
    IntPtr Function(
      IntPtr scManager,
      Pointer<Utf16> serviceName,
      Uint32 desiredAccess,
    );
typedef _OpenServiceDart =
    int Function(int scManager, Pointer<Utf16> serviceName, int desiredAccess);

typedef _QueryServiceStatusNative =
    Int32 Function(IntPtr service, Pointer<_ServiceStatus> status);
typedef _QueryServiceStatusDart =
    int Function(int service, Pointer<_ServiceStatus> status);

typedef _ControlServiceNative =
    Int32 Function(
      IntPtr service,
      Uint32 control,
      Pointer<_ServiceStatus> status,
    );
typedef _ControlServiceDart =
    int Function(int service, int control, Pointer<_ServiceStatus> status);

typedef _StartServiceNative =
    Int32 Function(
      IntPtr service,
      Uint32 numArgs,
      Pointer<Pointer<Utf16>> args,
    );
typedef _StartServiceDart =
    int Function(int service, int numArgs, Pointer<Pointer<Utf16>> args);

typedef _CloseServiceHandleNative = Int32 Function(IntPtr handle);
typedef _CloseServiceHandleDart = int Function(int handle);

typedef _InitiateShutdownNative =
    Int32 Function(
      Pointer<Utf16> machineName,
      Pointer<Utf16> message,
      Uint32 gracePeriod,
      Int32 forceAppsClosed,
      Int32 rebootAfterShutdown,
      Uint32 reason,
    );
typedef _InitiateShutdownDart =
    int Function(
      Pointer<Utf16> machineName,
      Pointer<Utf16> message,
      int gracePeriod,
      int forceAppsClosed,
      int rebootAfterShutdown,
      int reason,
    );

typedef _AbortShutdownNative = Int32 Function(Pointer<Utf16> machineName);
typedef _AbortShutdownDart = int Function(Pointer<Utf16> machineName);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

// --- Φόρτωση ---------------------------------------------------------------

final DynamicLibrary _winspool = DynamicLibrary.open('winspool.drv');
final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _kernel = DynamicLibrary.open('kernel32.dll');

final _enumPrinters = _winspool
    .lookupFunction<_EnumPrintersNative, _EnumPrintersDart>('EnumPrintersW');
final _openPrinter = _winspool
    .lookupFunction<_OpenPrinterNative, _OpenPrinterDart>('OpenPrinterW');
final _closePrinter = _winspool
    .lookupFunction<_ClosePrinterNative, _ClosePrinterDart>('ClosePrinter');
final _enumJobs = _winspool.lookupFunction<_EnumJobsNative, _EnumJobsDart>(
  'EnumJobsW',
);
final _setJob = _winspool.lookupFunction<_SetJobNative, _SetJobDart>('SetJobW');
final _deletePrinter = _winspool
    .lookupFunction<_DeletePrinterNative, _DeletePrinterDart>('DeletePrinter');
final _setPrinter = _winspool
    .lookupFunction<_SetPrinterNative, _SetPrinterDart>('SetPrinterW');

final _openScManager = _advapi
    .lookupFunction<_OpenScManagerNative, _OpenScManagerDart>('OpenSCManagerW');
final _openService = _advapi
    .lookupFunction<_OpenServiceNative, _OpenServiceDart>('OpenServiceW');
final _queryServiceStatus = _advapi
    .lookupFunction<_QueryServiceStatusNative, _QueryServiceStatusDart>(
      'QueryServiceStatus',
    );
final _controlService = _advapi
    .lookupFunction<_ControlServiceNative, _ControlServiceDart>(
      'ControlService',
    );
final _startService = _advapi
    .lookupFunction<_StartServiceNative, _StartServiceDart>('StartServiceW');
final _closeServiceHandle = _advapi
    .lookupFunction<_CloseServiceHandleNative, _CloseServiceHandleDart>(
      'CloseServiceHandle',
    );
final _initiateShutdown = _advapi
    .lookupFunction<_InitiateShutdownNative, _InitiateShutdownDart>(
      'InitiateSystemShutdownW',
    );
final _abortShutdown = _advapi
    .lookupFunction<_AbortShutdownNative, _AbortShutdownDart>(
      'AbortSystemShutdownW',
    );
final _getLastError = _kernel
    .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

/// Φορτώνει ΟΛΕΣ τις αναφορές πριν από την πρώτη πραγματική κλήση.
///
/// Τα top-level `final` του Dart είναι **τεμπέλικα**: η πρώτη χρήση τους
/// εκτελεί `DynamicLibrary.open` και `lookupFunction`, που είναι κλήσεις
/// Windows και **μηδενίζουν το last error**. Αν αυτό συμβεί ανάμεσα στην
/// αποτυχημένη κλήση και στο `GetLastError`, η αιτία χάνεται και διαβάζεται
/// ως «κωδικός 0» — σφάλμα χωρίς αιτία, που δεν οδηγεί πουθενά.
///
/// Βρέθηκε ζωντανά: η ίδια κλήση έδινε 1753 σε απομονωμένη δοκιμή και 0 μέσα
/// από την εφαρμογή.
bool _warmedUp = false;

void _warmUp() {
  if (_warmedUp) return;
  _warmedUp = true;
  final refs = <Object>[
    _enumPrinters,
    _openPrinter,
    _closePrinter,
    _enumJobs,
    _setJob,
    _deletePrinter,
    _openScManager,
    _openService,
    _queryServiceStatus,
    _controlService,
    _startService,
    _closeServiceHandle,
    _initiateShutdown,
    _abortShutdown,
    _getLastError,
  ];
  // Καθαρίζει ό,τι άφησαν πίσω τους τα φορτώματα.
  if (refs.isNotEmpty) _getLastError();
}

/// Ωμός εκτυπωτής — απλοί τύποι, ώστε να ταξιδεύει έξω από το isolate.
typedef RawPrinter = ({
  String name,
  String driverName,
  int status,
  int jobCount,
});

/// Ωμή εργασία εκτύπωσης.
typedef RawPrintJob = ({
  int jobId,
  String document,
  String user,
  String machine,
  int status,
  int totalPages,
  int pagesPrinted,
});

/// `PRINTER_ENUM_NAME` — απαρίθμηση των εκτυπωτών συγκεκριμένου διακομιστή.
const int _printerEnumName = 0x00000008;

/// `ERROR_INSUFFICIENT_BUFFER` — η αναμενόμενη αποτυχία της πρώτης κλήσης,
/// εκείνης που ρωτά «πόσο χώρο χρειάζεσαι;».
const int _errorInsufficientBuffer = 122;

/// `ERROR_MORE_DATA` — ισοδύναμη απάντηση από ορισμένες εκδόσεις.
const int _errorMoreData = 234;

/// `JOB_CONTROL_DELETE`.
const int _jobControlDelete = 5;

/// `PRINTER_CONTROL_RESUME` — ξεκολλάει εκτυπωτή που είναι σε παύση.
const int _printerControlResume = 2;

/// `SERVICE_CONTROL_STOP`.
const int _serviceControlStop = 1;

const int _scManagerConnect = 0x0001;
const int _serviceQueryStatus = 0x0004;
const int _serviceStart = 0x0010;
const int _serviceStop = 0x0020;
const int _serviceStopped = 1;
const int _serviceRunning = 4;

/// `SHTDN_REASON_MAJOR_OPERATINGSYSTEM | SHTDN_REASON_MINOR_MAINTENANCE`
/// με τη σημαία «σχεδιασμένο» — ώστε το αρχείο συμβάντων του διακομιστή να
/// καταγράφει προγραμματισμένη συντήρηση και όχι ανώμαλο τερματισμό.
const int _shutdownReasonPlannedMaintenance = 0x80020001;

abstract final class WindowsPrinterFfi {
  WindowsPrinterFfi._();

  /// Οι εκτυπωτές ενός διακομιστή.
  static ({bool ok, int code, List<RawPrinter> printers}) enumeratePrinters(
    String host,
  ) {
    _warmUp();
    final namePtr = '\\\\$host'.toNativeUtf16();
    final needed = calloc<Uint32>();
    final returned = calloc<Uint32>();
    try {
      // Πρώτη κλήση με μηδενικό buffer: μαθαίνουμε πόσα bytes θέλει.
      //
      // Αυτή η κλήση ΠΑΝΤΑ αποτυγχάνει — το ερώτημα είναι με ΤΙ. Μόνο το
      // «δεν χωράει ο buffer» σημαίνει «όλα καλά, ξαναρώτα με χώρο». Κάθε
      // άλλος κωδικός είναι πραγματικό σφάλμα, και αν τον αγνοήσουμε
      // επιστρέφουμε άδεια λίστα: ο χειριστής διαβάζει «κανένας εκτυπωτής»
      // ενώ στην πραγματικότητα ο διακομιστής αρνήθηκε την πρόσβαση.
      final probe = _enumPrinters(
        _printerEnumName,
        namePtr,
        2,
        nullptr,
        0,
        needed,
        returned,
      );
      if (probe == 0) {
        final err = _getLastError();
        if (err != _errorInsufficientBuffer && err != _errorMoreData) {
          return (ok: false, code: err, printers: const []);
        }
      }
      final size = needed.value;
      if (size == 0) return (ok: true, code: 0, printers: const []);

      final buffer = calloc<Uint8>(size);
      try {
        final ok = _enumPrinters(
          _printerEnumName,
          namePtr,
          2,
          buffer,
          size,
          needed,
          returned,
        );
        if (ok == 0) {
          return (ok: false, code: _getLastError(), printers: const []);
        }

        final base = buffer.cast<_PrinterInfo2>();
        final out = <RawPrinter>[];
        for (var i = 0; i < returned.value; i++) {
          final info = (base + i).ref;
          out.add((
            name: _readUtf16(info.pPrinterName),
            driverName: _readUtf16(info.pDriverName),
            status: info.status,
            jobCount: info.cJobs,
          ));
        }
        return (ok: true, code: 0, printers: out);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(needed);
      calloc.free(returned);
    }
  }

  /// Οι εργασίες στην ουρά ενός εκτυπωτή.
  static ({bool ok, int code, List<RawPrintJob> jobs}) enumerateJobs(
    String printerName,
  ) {
    _warmUp();
    final namePtr = printerName.toNativeUtf16();
    final handle = calloc<IntPtr>();
    final needed = calloc<Uint32>();
    final returned = calloc<Uint32>();
    var opened = 0;
    try {
      if (_openPrinter(namePtr, handle, nullptr) == 0) {
        return (ok: false, code: _getLastError(), jobs: const []);
      }
      opened = handle.value;

      // Ίδιο μοτίβο με τους εκτυπωτές: η αποτυχία της πρώτης κλήσης είναι
      // αναμενόμενη μόνο όταν φταίει ο μηδενικός buffer.
      final probe = _enumJobs(
        opened,
        0,
        0xFFFFFFFF,
        1,
        nullptr,
        0,
        needed,
        returned,
      );
      if (probe == 0) {
        final err = _getLastError();
        if (err != _errorInsufficientBuffer && err != _errorMoreData) {
          return (ok: false, code: err, jobs: const []);
        }
      }
      final size = needed.value;
      if (size == 0) return (ok: true, code: 0, jobs: const []);

      final buffer = calloc<Uint8>(size);
      try {
        final ok = _enumJobs(
          opened,
          0,
          0xFFFFFFFF,
          1,
          buffer,
          size,
          needed,
          returned,
        );
        if (ok == 0) return (ok: false, code: _getLastError(), jobs: const []);

        final base = buffer.cast<_JobInfo1>();
        final out = <RawPrintJob>[];
        for (var i = 0; i < returned.value; i++) {
          final job = (base + i).ref;
          out.add((
            jobId: job.jobId,
            document: _readUtf16(job.pDocument),
            user: _readUtf16(job.pUserName),
            machine: _readUtf16(job.pMachineName),
            status: job.status,
            totalPages: job.totalPages,
            pagesPrinted: job.pagesPrinted,
          ));
        }
        return (ok: true, code: 0, jobs: out);
      } finally {
        calloc.free(buffer);
      }
    } finally {
      if (opened != 0) _closePrinter(opened);
      calloc.free(namePtr);
      calloc.free(handle);
      calloc.free(needed);
      calloc.free(returned);
    }
  }

  /// Σβήνει όλες τις εργασίες ενός εκτυπωτή. Επιστρέφει πόσες σβήστηκαν.
  static ({bool ok, int code, int deleted}) purgeQueue(String printerName) {
    _warmUp();
    final listed = enumerateJobs(printerName);
    if (!listed.ok) return (ok: false, code: listed.code, deleted: 0);
    if (listed.jobs.isEmpty) return (ok: true, code: 0, deleted: 0);

    final namePtr = printerName.toNativeUtf16();
    final handle = calloc<IntPtr>();
    var opened = 0;
    try {
      if (_openPrinter(namePtr, handle, nullptr) == 0) {
        return (ok: false, code: _getLastError(), deleted: 0);
      }
      opened = handle.value;

      var deleted = 0;
      var lastError = 0;
      for (final job in listed.jobs) {
        final ok = _setJob(opened, job.jobId, 0, nullptr, _jobControlDelete);
        if (ok != 0) {
          deleted++;
        } else {
          lastError = _getLastError();
        }
      }
      // Μερική επιτυχία μετράει ως επιτυχία: μια εργασία που πρόλαβε να
      // τελειώσει μόνη της δεν είναι σφάλμα προς τον χειριστή.
      if (deleted == 0 && lastError != 0) {
        return (ok: false, code: lastError, deleted: 0);
      }
      return (ok: true, code: 0, deleted: deleted);
    } finally {
      if (opened != 0) _closePrinter(opened);
      calloc.free(namePtr);
      calloc.free(handle);
    }
  }

  /// Αφαιρεί εκτυπωτή από τον διακομιστή (για ορφανούς).
  static ({bool ok, int code}) deletePrinter(String printerName) {
    _warmUp();
    final namePtr = printerName.toNativeUtf16();
    final handle = calloc<IntPtr>();
    var opened = 0;
    try {
      if (_openPrinter(namePtr, handle, nullptr) == 0) {
        return (ok: false, code: _getLastError());
      }
      opened = handle.value;
      final ok = _deletePrinter(opened);
      if (ok == 0) return (ok: false, code: _getLastError());
      return (ok: true, code: 0);
    } finally {
      if (opened != 0) _closePrinter(opened);
      calloc.free(namePtr);
      calloc.free(handle);
    }
  }

  /// Ξεπαγώνει εκτυπωτή που βρίσκεται σε παύση.
  ///
  /// Το φθηνότερο σκαλί επαναφοράς: δεν αγγίζει καμία συνεδρία, δεν κόβει
  /// καμία εκτύπωση, και κανείς δεν το αντιλαμβάνεται. Έχει νόημα μόνο όταν ο
  /// εκτυπωτής **υπάρχει** στον διακομιστή αλλά δηλώνει παύση.
  static ({bool ok, int code}) resumePrinter(String printerName) {
    _warmUp();
    final namePtr = printerName.toNativeUtf16();
    final handle = calloc<IntPtr>();
    var opened = 0;
    try {
      if (_openPrinter(namePtr, handle, nullptr) == 0) {
        return (ok: false, code: _getLastError());
      }
      opened = handle.value;
      final ok = _setPrinter(opened, 0, nullptr, _printerControlResume);
      if (ok == 0) return (ok: false, code: _getLastError());
      return (ok: true, code: 0);
    } finally {
      if (opened != 0) _closePrinter(opened);
      calloc.free(namePtr);
      calloc.free(handle);
    }
  }

  /// Σταματά και ξαναξεκινά μια υπηρεσία σε απομακρυσμένο μηχάνημα.
  ///
  /// Περιμένει να σταματήσει πραγματικά πριν ξεκινήσει ξανά: ένα `start` πάνω
  /// σε υπηρεσία που ακόμη κλείνει αποτυγχάνει και αφήνει τον διακομιστή
  /// **χωρίς** ουρά εκτυπώσεων.
  static ({bool ok, int code}) restartService({
    required String host,
    required String serviceName,
    Duration stopTimeout = const Duration(seconds: 20),
  }) {
    _warmUp();
    final machinePtr = '\\\\$host'.toNativeUtf16();
    final namePtr = serviceName.toNativeUtf16();
    final status = calloc<_ServiceStatus>();
    var scm = 0;
    var service = 0;
    try {
      scm = _openScManager(machinePtr, nullptr, _scManagerConnect);
      if (scm == 0) return (ok: false, code: _getLastError());

      service = _openService(
        scm,
        namePtr,
        _serviceQueryStatus | _serviceStart | _serviceStop,
      );
      if (service == 0) return (ok: false, code: _getLastError());

      if (_queryServiceStatus(service, status) == 0) {
        return (ok: false, code: _getLastError());
      }

      if (status.ref.currentState != _serviceStopped) {
        if (_controlService(service, _serviceControlStop, status) == 0) {
          return (ok: false, code: _getLastError());
        }
        final deadline = stopTimeout.inMilliseconds;
        var waited = 0;
        while (waited < deadline) {
          sleep(const Duration(milliseconds: 400));
          waited += 400;
          if (_queryServiceStatus(service, status) == 0) break;
          if (status.ref.currentState == _serviceStopped) break;
        }
        if (status.ref.currentState != _serviceStopped) {
          return (ok: false, code: ServerPrinterMessages.serviceStopTimedOut);
        }
      }

      if (_startService(service, 0, nullptr) == 0) {
        return (ok: false, code: _getLastError());
      }

      // Επαλήθευση: η υπηρεσία πρέπει να τρέχει, όχι απλώς να έχει δεχτεί την
      // εντολή. Χωρίς αυτό, μια αποτυχημένη εκκίνηση θα περνούσε για επιτυχία.
      var waited = 0;
      while (waited < 15000) {
        sleep(const Duration(milliseconds: 400));
        waited += 400;
        if (_queryServiceStatus(service, status) == 0) break;
        if (status.ref.currentState == _serviceRunning) {
          return (ok: true, code: 0);
        }
      }
      return (ok: false, code: ServerPrinterMessages.serviceStartTimedOut);
    } finally {
      if (service != 0) _closeServiceHandle(service);
      if (scm != 0) _closeServiceHandle(scm);
      calloc.free(machinePtr);
      calloc.free(namePtr);
      calloc.free(status);
    }
  }

  /// Επιτρέπεται η **διαχείριση** μιας υπηρεσίας, χωρίς να την πειράξουμε;
  ///
  /// Ζητά από τα Windows να ανοίξουν την υπηρεσία με δικαίωμα διακοπής και
  /// εκκίνησης, και **σταματά εκεί**: το άνοιγμα από μόνο του απαντά αν ο
  /// λογαριασμός έχει τα δικαιώματα. Καμία εντολή δεν στέλνεται, καμία ουρά
  /// δεν σταματά — γι' αυτό ο έλεγχος μπορεί να τρέχει σε ζωντανό διακομιστή.
  static ({bool ok, int code}) probeServiceControl({
    required String host,
    required String serviceName,
  }) {
    _warmUp();
    final machinePtr = '\\\\$host'.toNativeUtf16();
    final namePtr = serviceName.toNativeUtf16();
    var scm = 0;
    var service = 0;
    try {
      scm = _openScManager(machinePtr, nullptr, _scManagerConnect);
      if (scm == 0) return (ok: false, code: _getLastError());
      service = _openService(
        scm,
        namePtr,
        _serviceQueryStatus | _serviceStart | _serviceStop,
      );
      if (service == 0) return (ok: false, code: _getLastError());
      return (ok: true, code: 0);
    } finally {
      if (service != 0) _closeServiceHandle(service);
      if (scm != 0) _closeServiceHandle(scm);
      calloc.free(machinePtr);
      calloc.free(namePtr);
    }
  }

  /// Η τρέχουσα κατάσταση μιας υπηρεσίας σε απομακρυσμένο μηχάνημα.
  static ({bool ok, int code, int state}) serviceState({
    required String host,
    required String serviceName,
  }) {
    final machinePtr = '\\\\$host'.toNativeUtf16();
    final namePtr = serviceName.toNativeUtf16();
    final status = calloc<_ServiceStatus>();
    var scm = 0;
    var service = 0;
    try {
      scm = _openScManager(machinePtr, nullptr, _scManagerConnect);
      if (scm == 0) return (ok: false, code: _getLastError(), state: 0);
      service = _openService(scm, namePtr, _serviceQueryStatus);
      if (service == 0) return (ok: false, code: _getLastError(), state: 0);
      if (_queryServiceStatus(service, status) == 0) {
        return (ok: false, code: _getLastError(), state: 0);
      }
      return (ok: true, code: 0, state: status.ref.currentState);
    } finally {
      if (service != 0) _closeServiceHandle(service);
      if (scm != 0) _closeServiceHandle(scm);
      calloc.free(machinePtr);
      calloc.free(namePtr);
      calloc.free(status);
    }
  }

  /// Ξεκινά επανεκκίνηση με προειδοποίηση προς όσους είναι συνδεδεμένοι.
  ///
  /// Το [message] εμφανίζεται στις οθόνες τους και το [graceSeconds] είναι ο
  /// χρόνος που έχουν να σώσουν — μέσα σε αυτόν, η [abortRestart] ακυρώνει.
  static ({bool ok, int code}) initiateRestart({
    required String host,
    required String message,
    required int graceSeconds,
    bool forceAppsClosed = false,
  }) {
    _warmUp();
    final machinePtr = '\\\\$host'.toNativeUtf16();
    final messagePtr = message.toNativeUtf16();
    try {
      final ok = _initiateShutdown(
        machinePtr,
        messagePtr,
        graceSeconds,
        forceAppsClosed ? 1 : 0,
        1, // rebootAfterShutdown
        _shutdownReasonPlannedMaintenance,
      );
      if (ok == 0) return (ok: false, code: _getLastError());
      return (ok: true, code: 0);
    } finally {
      calloc.free(machinePtr);
      calloc.free(messagePtr);
    }
  }

  /// Ακυρώνει επανεκκίνηση που μετράει αντίστροφα.
  static ({bool ok, int code}) abortRestart(String host) {
    _warmUp();
    final machinePtr = '\\\\$host'.toNativeUtf16();
    try {
      final ok = _abortShutdown(machinePtr);
      if (ok == 0) return (ok: false, code: _getLastError());
      return (ok: true, code: 0);
    } finally {
      calloc.free(machinePtr);
    }
  }

  static String _readUtf16(Pointer<Utf16> p) =>
      p == nullptr ? '' : p.toDartString().trim();
}
