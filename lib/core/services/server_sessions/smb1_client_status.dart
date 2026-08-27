/// Έλεγχος του «SMB 1.0/CIFS Client» σε αυτόν τον υπολογιστή.
///
/// Οι διακομιστές είναι Windows Server 2003 και το κανάλι που μεταφέρει τις
/// κλήσεις συνεδρίας περνά μέσα από SMB1 — το οποίο τα Windows 11 **δεν**
/// εγκαθιστούν από προεπιλογή. Χωρίς αυτό, κάθε ερώτηση επιστρέφει σφάλμα που
/// μοιάζει με «ο διακομιστής δεν απαντά» και ο χειριστής ψάχνει σε λάθος
/// κατεύθυνση. Γι' αυτό ο έλεγχος στέκεται ορατός στην οθόνη διακομιστών,
/// όπως και στο έργο TEP Remote.
///
/// Ρωτάμε απευθείας τον Service Control Manager για τον οδηγό `mrxsmb10` και
/// **όχι** το `sc.exe`: η έξοδος του εργαλείου είναι κείμενο προς ανάγνωση από
/// άνθρωπο, με σειρά πεδίων και λεκτικά που δεν είναι συμβόλαιο.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'server_session_models.dart';

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

typedef _CloseServiceHandleNative = Int32 Function(IntPtr handle);
typedef _CloseServiceHandleDart = int Function(int handle);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

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

const int _scManagerConnect = 0x0001;
const int _serviceQueryStatus = 0x0004;

/// `SERVICE_RUNNING`.
const int kServiceRunning = 4;

/// `ERROR_SERVICE_DOES_NOT_EXIST` — ο οδηγός δεν είναι καν εγκατεστημένος.
const int kErrorServiceDoesNotExist = 1060;

abstract final class Smb1ClientCheck {
  Smb1ClientCheck._();

  static Future<Smb1ClientStatus> current() async {
    if (!Platform.isWindows) return Smb1ClientStatus.unknown;
    return _query();
  }

  /// Μετάφραση του ωμού αποτελέσματος σε κατάσταση — καθαρή, χωρίς Windows.
  ///
  /// [openError] είναι `null` όταν το άνοιγμα πέτυχε. [state] είναι `null`
  /// όταν ο οδηγός βρέθηκε αλλά η κατάστασή του δεν διαβάστηκε.
  static Smb1ClientStatus statusFrom({int? openError, int? state}) {
    if (openError == kErrorServiceDoesNotExist) return Smb1ClientStatus.missing;
    if (openError != null) return Smb1ClientStatus.unknown;
    if (state == null) return Smb1ClientStatus.unknown;
    return state == kServiceRunning
        ? Smb1ClientStatus.running
        : Smb1ClientStatus.installedNotRunning;
  }

  static Smb1ClientStatus _query() {
    try {
      final advapi = DynamicLibrary.open('advapi32.dll');
      final kernel = DynamicLibrary.open('kernel32.dll');
      final openScManager = advapi
          .lookupFunction<_OpenScManagerNative, _OpenScManagerDart>(
            'OpenSCManagerW',
          );
      final openService = advapi
          .lookupFunction<_OpenServiceNative, _OpenServiceDart>('OpenServiceW');
      final queryStatus = advapi
          .lookupFunction<_QueryServiceStatusNative, _QueryServiceStatusDart>(
            'QueryServiceStatus',
          );
      final closeHandle = advapi
          .lookupFunction<_CloseServiceHandleNative, _CloseServiceHandleDart>(
            'CloseServiceHandle',
          );
      final getLastError = kernel
          .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
            'GetLastError',
          );

      final scm = openScManager(nullptr, nullptr, _scManagerConnect);
      if (scm == 0) return Smb1ClientStatus.unknown;

      final namePtr = 'mrxsmb10'.toNativeUtf16();
      var service = 0;
      final statusPtr = calloc<_ServiceStatus>();
      try {
        service = openService(scm, namePtr, _serviceQueryStatus);
        if (service == 0) {
          return statusFrom(openError: getLastError());
        }
        final ok = queryStatus(service, statusPtr);
        if (ok == 0) return statusFrom(state: null);
        return statusFrom(state: statusPtr.ref.currentState);
      } finally {
        if (service != 0) closeHandle(service);
        closeHandle(scm);
        calloc.free(namePtr);
        calloc.free(statusPtr);
      }
    } catch (_) {
      return Smb1ClientStatus.unknown;
    }
  }
}

/// Ανοίγει το παράθυρο «Δυνατότητες των Windows», όπου ενεργοποιείται το SMB1.
///
/// Επιστρέφει `false` όταν δεν άνοιξε — ο καλών το λέει στον χειριστή αντί να
/// τον αφήσει να περιμένει παράθυρο που δεν έρχεται.
Future<bool> openWindowsOptionalFeatures() async {
  if (!Platform.isWindows) return false;
  try {
    final windir = Platform.environment['windir'] ?? r'C:\Windows';
    await Process.start(
      '$windir\\System32\\optionalfeatures.exe',
      const [],
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}
