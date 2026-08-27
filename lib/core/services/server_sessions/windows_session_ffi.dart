/// Απευθείας κλήσεις προς τα Windows API για συνεδρίες Terminal Services.
///
/// Γράφτηκαν εδώ και δεν ήρθαν από το `win32`, γιατί το πακέτο δεν εκθέτει
/// ούτε τα `WTS*` ούτε τα `WNet*`.
///
/// **Το κλειδί όλου του μηχανισμού:** η ταυτότητα με την οποία ταξιδεύει η
/// κλήση RPC προς τον διακομιστή **ακολουθεί την ανοιχτή συνεδρία SMB**. Γι'
/// αυτό ανοίγουμε πρώτα σύνδεση προς το `IPC$` του διακομιστή με τα στοιχεία
/// του διαχειριστή, και μόνο τότε ρωτάμε ή τερματίζουμε συνεδρίες.
/// Επιβεβαιωμένο ζωντανά στον 192.168.13.82 (Windows Server 2003): χωρίς αυτό,
/// ακόμη κι ο ίδιος ο λογαριασμός παίρνει «άρνηση πρόσβασης» για τη δική του
/// συνεδρία.
///
/// Όλες οι συναρτήσεις **μπλοκάρουν**. Καλούνται μέσα από `Isolate.run` ώστε
/// να μην παγώνει το παράθυρο όσο ο διακομιστής αργεί.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// --- Δομές -----------------------------------------------------------------

final class _NetResourceW extends Struct {
  @Uint32()
  external int dwScope;
  @Uint32()
  external int dwType;
  @Uint32()
  external int dwDisplayType;
  @Uint32()
  external int dwUsage;
  external Pointer<Utf16> lpLocalName;
  external Pointer<Utf16> lpRemoteName;
  external Pointer<Utf16> lpComment;
  external Pointer<Utf16> lpProvider;
}

final class _WtsSessionInfoW extends Struct {
  @Uint32()
  external int sessionId;
  external Pointer<Utf16> pWinStationName;
  @Int32()
  external int state;
}

// --- Υπογραφές -------------------------------------------------------------

typedef _WNetAddConnection2Native =
    Uint32 Function(
      Pointer<_NetResourceW> netResource,
      Pointer<Utf16> password,
      Pointer<Utf16> username,
      Uint32 flags,
    );
typedef _WNetAddConnection2Dart =
    int Function(
      Pointer<_NetResourceW> netResource,
      Pointer<Utf16> password,
      Pointer<Utf16> username,
      int flags,
    );

typedef _WNetCancelConnection2Native =
    Uint32 Function(Pointer<Utf16> name, Uint32 flags, Int32 force);
typedef _WNetCancelConnection2Dart =
    int Function(Pointer<Utf16> name, int flags, int force);

typedef _WtsOpenServerNative = IntPtr Function(Pointer<Utf16> serverName);
typedef _WtsOpenServerDart = int Function(Pointer<Utf16> serverName);

typedef _WtsCloseServerNative = Void Function(IntPtr server);
typedef _WtsCloseServerDart = void Function(int server);

typedef _WtsEnumerateSessionsNative =
    Int32 Function(
      IntPtr server,
      Uint32 reserved,
      Uint32 version,
      Pointer<Pointer<_WtsSessionInfoW>> ppSessionInfo,
      Pointer<Uint32> pCount,
    );
typedef _WtsEnumerateSessionsDart =
    int Function(
      int server,
      int reserved,
      int version,
      Pointer<Pointer<_WtsSessionInfoW>> ppSessionInfo,
      Pointer<Uint32> pCount,
    );

typedef _WtsQuerySessionInformationNative =
    Int32 Function(
      IntPtr server,
      Uint32 sessionId,
      Int32 infoClass,
      Pointer<Pointer<Utf16>> ppBuffer,
      Pointer<Uint32> pBytesReturned,
    );
typedef _WtsQuerySessionInformationDart =
    int Function(
      int server,
      int sessionId,
      int infoClass,
      Pointer<Pointer<Utf16>> ppBuffer,
      Pointer<Uint32> pBytesReturned,
    );

typedef _WtsFreeMemoryNative = Void Function(Pointer<NativeType> memory);
typedef _WtsFreeMemoryDart = void Function(Pointer<NativeType> memory);

typedef _WtsLogoffSessionNative =
    Int32 Function(IntPtr server, Uint32 sessionId, Int32 wait);
typedef _WtsLogoffSessionDart =
    int Function(int server, int sessionId, int wait);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

// --- Φόρτωση βιβλιοθηκών ---------------------------------------------------
// Lazy ανά isolate: κάθε `Isolate.run` φορτώνει τις δικές του αναφορές.

final DynamicLibrary _mpr = DynamicLibrary.open('mpr.dll');
final DynamicLibrary _wts = DynamicLibrary.open('wtsapi32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _wNetAddConnection2 = _mpr
    .lookupFunction<_WNetAddConnection2Native, _WNetAddConnection2Dart>(
      'WNetAddConnection2W',
    );
final _wNetCancelConnection2 = _mpr
    .lookupFunction<_WNetCancelConnection2Native, _WNetCancelConnection2Dart>(
      'WNetCancelConnection2W',
    );
final _wtsOpenServer = _wts
    .lookupFunction<_WtsOpenServerNative, _WtsOpenServerDart>('WTSOpenServerW');
final _wtsCloseServer = _wts
    .lookupFunction<_WtsCloseServerNative, _WtsCloseServerDart>(
      'WTSCloseServer',
    );
final _wtsEnumerateSessions = _wts
    .lookupFunction<_WtsEnumerateSessionsNative, _WtsEnumerateSessionsDart>(
      'WTSEnumerateSessionsW',
    );
final _wtsQuerySessionInformation = _wts
    .lookupFunction<
      _WtsQuerySessionInformationNative,
      _WtsQuerySessionInformationDart
    >('WTSQuerySessionInformationW');
final _wtsFreeMemory = _wts
    .lookupFunction<_WtsFreeMemoryNative, _WtsFreeMemoryDart>('WTSFreeMemory');
final _wtsLogoffSession = _wts
    .lookupFunction<_WtsLogoffSessionNative, _WtsLogoffSessionDart>(
      'WTSLogoffSession',
    );
final _getLastError = _kernel32
    .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

/// Φορτώνει ΟΛΕΣ τις αναφορές πριν από την πρώτη πραγματική κλήση.
///
/// Τα top-level `final` του Dart είναι **τεμπέλικα**: η πρώτη χρήση τους
/// εκτελεί `DynamicLibrary.open` και `lookupFunction`, που είναι κλήσεις
/// Windows και **μηδενίζουν το last error**. Αν αυτό συμβεί ανάμεσα στην
/// αποτυχημένη κλήση και στο `GetLastError`, η αιτία χάνεται και διαβάζεται
/// ως «κωδικός 0» — σφάλμα χωρίς αιτία, που δεν οδηγεί πουθενά.
bool _warmedUp = false;

void _warmUp() {
  if (_warmedUp) return;
  _warmedUp = true;
  final refs = <Object>[
    _wNetAddConnection2,
    _wNetCancelConnection2,
    _wtsOpenServer,
    _wtsCloseServer,
    _wtsEnumerateSessions,
    _wtsQuerySessionInformation,
    _wtsFreeMemory,
    _wtsLogoffSession,
    _getLastError,
  ];
  // Καθαρίζει ό,τι άφησαν πίσω τους τα φορτώματα.
  if (refs.isNotEmpty) _getLastError();
}

/// Ωμή συνεδρία όπως την επιστρέφει το API, πριν γίνει μοντέλο της εφαρμογής.
///
/// Απλοί τύποι μόνο, ώστε να ταξιδεύει από το isolate πίσω στο UI.
typedef RawServerSession = ({
  int sessionId,
  String username,
  int state,
  String stationName,
  String winStationName,
});

/// Το αποτέλεσμα μιας ωμής κλήσης: επιτυχία ή κωδικός σφάλματος των Windows.
typedef RawApiResult = ({bool ok, int code, List<RawServerSession> sessions});

/// Κλάσεις πληροφορίας του `WTSQuerySessionInformation`.
const int _wtsUserName = 5;
const int _wtsClientName = 10;

/// Χαμηλού επιπέδου κλήσεις. Όλες μπλοκάρουν το νήμα τους.
abstract final class WindowsSessionFfi {
  WindowsSessionFfi._();

  static bool get isSupportedPlatform => Platform.isWindows;

  /// Ανοίγει συνεδρία SMB προς `\\<host>\IPC$` — ό,τι κάνει το `net use`.
  ///
  /// Καθαρίζει πρώτα τυχόν προηγούμενη σύνδεση: μια ανοιχτή συνεδρία με άλλα
  /// στοιχεία μπλοκάρει τη νέα με σφάλμα 1219, και το σύμπτωμα μοιάζει με
  /// «λάθος κωδικός».
  static int connectIpcShare({
    required String host,
    required String user,
    required String password,
  }) {
    final remote = '\\\\$host\\IPC\$';
    disconnectShare(host);

    final resource = calloc<_NetResourceW>();
    final remotePtr = remote.toNativeUtf16();
    final userPtr = user.toNativeUtf16();
    final passPtr = password.toNativeUtf16();
    try {
      resource.ref.dwType = 0; // RESOURCETYPE_ANY
      resource.ref.lpRemoteName = remotePtr;
      return _wNetAddConnection2(resource, passPtr, userPtr, 0);
    } finally {
      calloc.free(resource);
      calloc.free(remotePtr);
      calloc.free(userPtr);
      calloc.free(passPtr);
    }
  }

  /// Κλείνει κάθε συνεδρία SMB προς τον διακομιστή.
  ///
  /// Καλείται **πάντα** στο τέλος: δεν μένει ανοιχτή συνεδρία διαχειριστή σε
  /// υπολογιστή γραφείου.
  static void disconnectShare(String host) {
    _warmUp();
    final ipc = '\\\\$host\\IPC\$'.toNativeUtf16();
    final root = '\\\\$host'.toNativeUtf16();
    try {
      _wNetCancelConnection2(ipc, 0, 1);
      _wNetCancelConnection2(root, 0, 1);
    } finally {
      calloc.free(ipc);
      calloc.free(root);
    }
  }

  /// Απαριθμεί τις συνεδρίες. Προϋποθέτει ανοιχτή συνεδρία SMB.
  static RawApiResult enumerateSessions(String host) {
    _warmUp();
    final hostPtr = host.toNativeUtf16();
    var server = 0;
    try {
      server = _wtsOpenServer(hostPtr);
      if (server == 0) {
        return (ok: false, code: _getLastError(), sessions: const []);
      }

      final ppInfo = calloc<Pointer<_WtsSessionInfoW>>();
      final pCount = calloc<Uint32>();
      try {
        final ok = _wtsEnumerateSessions(server, 0, 1, ppInfo, pCount);
        if (ok == 0) {
          return (ok: false, code: _getLastError(), sessions: const []);
        }

        final count = pCount.value;
        final base = ppInfo.value;
        final out = <RawServerSession>[];
        for (var i = 0; i < count; i++) {
          final entry = (base + i).ref;
          final id = entry.sessionId;
          out.add((
            sessionId: id,
            username: _queryString(server, id, _wtsUserName),
            state: entry.state,
            stationName: _queryString(server, id, _wtsClientName),
            winStationName: entry.pWinStationName == nullptr
                ? ''
                : entry.pWinStationName.toDartString(),
          ));
        }
        _wtsFreeMemory(base.cast());
        return (ok: true, code: 0, sessions: out);
      } finally {
        calloc.free(ppInfo);
        calloc.free(pCount);
      }
    } finally {
      if (server != 0) _wtsCloseServer(server);
      calloc.free(hostPtr);
    }
  }

  /// Τερματίζει (logoff) μια συνεδρία. Προϋποθέτει ανοιχτή συνεδρία SMB.
  static ({bool ok, int code}) logoffSession({
    required String host,
    required int sessionId,
  }) {
    _warmUp();
    final hostPtr = host.toNativeUtf16();
    var server = 0;
    try {
      server = _wtsOpenServer(hostPtr);
      if (server == 0) return (ok: false, code: _getLastError());
      final ok = _wtsLogoffSession(server, sessionId, 1);
      if (ok != 0) return (ok: true, code: 0);
      return (ok: false, code: _getLastError());
    } finally {
      if (server != 0) _wtsCloseServer(server);
      calloc.free(hostPtr);
    }
  }

  /// Διαβάζει ένα κείμενο για μια συνεδρία· κενό όταν ο διακομιστής δεν απαντά.
  ///
  /// Η αποτυχία είναι σιωπηλή επίτηδες: το όνομα σταθμού είναι **προαιρετική**
  /// πληροφορία και δεν πρέπει ποτέ να χαλάει την εμφάνιση της λίστας.
  static String _queryString(int server, int sessionId, int infoClass) {
    final ppBuffer = calloc<Pointer<Utf16>>();
    final pBytes = calloc<Uint32>();
    try {
      final ok = _wtsQuerySessionInformation(
        server,
        sessionId,
        infoClass,
        ppBuffer,
        pBytes,
      );
      if (ok == 0 || ppBuffer.value == nullptr) return '';
      final value = ppBuffer.value.toDartString();
      _wtsFreeMemory(ppBuffer.value.cast());
      return value.trim();
    } catch (_) {
      return '';
    } finally {
      calloc.free(ppBuffer);
      calloc.free(pBytes);
    }
  }
}
