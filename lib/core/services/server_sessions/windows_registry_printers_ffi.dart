/// Ανάγνωση των εκτυπωτών ενός διακομιστή **από το μητρώο του**.
///
/// Είναι η εφεδρική διαδρομή όταν η κανονική — η υπηρεσία ουράς εκτυπώσεων —
/// δεν απαντά. Και δεν απαντά για συγκεκριμένο λόγο: τα Windows 11 μιλούν
/// στους απομακρυσμένους εκτυπωτές μέσω RPC over TCP, ενώ ο Windows Server
/// 2003 ακούει μόνο σε named pipe. Το σύμπτωμα είναι ο κωδικός 1753
/// («δεν υπάρχει καταχωρημένο σημείο επικοινωνίας»), επιβεβαιωμένο ζωντανά
/// στον 192.168.13.82.
///
/// Το μητρώο, αντίθετα, ταξιδεύει πάνω από το ίδιο κανάλι SMB που ήδη
/// χρησιμοποιούν οι συνεδρίες — γι' αυτό δουλεύει χωρίς καμία αλλαγή
/// ρυθμίσεων. Δίνει **ονόματα, οδηγό και θύρα**, αλλά όχι ουρές: το πόσα
/// έγγραφα περιμένουν είναι στιγμιαία κατάσταση της υπηρεσίας, όχι
/// αποθηκευμένη ρύθμιση.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _RegConnectNative =
    Int32 Function(Pointer<Utf16> machine, IntPtr key, Pointer<IntPtr> result);
typedef _RegConnectDart =
    int Function(Pointer<Utf16> machine, int key, Pointer<IntPtr> result);

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

typedef _RegEnumKeyExNative =
    Int32 Function(
      IntPtr key,
      Uint32 index,
      Pointer<Utf16> name,
      Pointer<Uint32> nameLen,
      Pointer<Uint32> reserved,
      Pointer<Utf16> className,
      Pointer<Uint32> classLen,
      Pointer<NativeType> lastWrite,
    );
typedef _RegEnumKeyExDart =
    int Function(
      int key,
      int index,
      Pointer<Utf16> name,
      Pointer<Uint32> nameLen,
      Pointer<Uint32> reserved,
      Pointer<Utf16> className,
      Pointer<Uint32> classLen,
      Pointer<NativeType> lastWrite,
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

const int _hkeyLocalMachine = 0x80000002;
const int _keyRead = 0x20019;
const String _printersPath =
    r'SYSTEM\CurrentControlSet\Control\Print\Printers';

/// Μέγιστο μήκος ονόματος κλειδιού μητρώου, σε χαρακτήρες.
const int _maxKeyNameChars = 512;

final DynamicLibrary _advapi = DynamicLibrary.open('advapi32.dll');

final _regConnect = _advapi
    .lookupFunction<_RegConnectNative, _RegConnectDart>('RegConnectRegistryW');
final _regOpenKeyEx = _advapi
    .lookupFunction<_RegOpenKeyExNative, _RegOpenKeyExDart>('RegOpenKeyExW');
final _regEnumKeyEx = _advapi
    .lookupFunction<_RegEnumKeyExNative, _RegEnumKeyExDart>('RegEnumKeyExW');
final _regQueryValueEx = _advapi
    .lookupFunction<_RegQueryValueExNative, _RegQueryValueExDart>(
      'RegQueryValueExW',
    );
final _regCloseKey = _advapi
    .lookupFunction<_RegCloseKeyNative, _RegCloseKeyDart>('RegCloseKey');

/// Ωμός εκτυπωτής από το μητρώο — χωρίς ουρά και χωρίς ζωντανή κατάσταση.
typedef RawRegistryPrinter = ({String name, String driverName, String port});

abstract final class WindowsRegistryPrintersFfi {
  WindowsRegistryPrintersFfi._();

  /// Οι εκτυπωτές του διακομιστή, από το μητρώο του.
  ///
  /// Προϋποθέτει ανοιχτή συνεδρία SMB με στοιχεία διαχειριστή, όπως και οι
  /// υπόλοιπες κλήσεις.
  static ({bool ok, int code, List<RawRegistryPrinter> printers})
  enumeratePrinters(String host) {
    final machine = '\\\\$host'.toNativeUtf16();
    final hRoot = calloc<IntPtr>();
    var rootOpen = false;
    try {
      final connectRc = _regConnect(machine, _hkeyLocalMachine, hRoot);
      if (connectRc != 0) {
        return (ok: false, code: connectRc, printers: const []);
      }
      rootOpen = true;

      final subKey = _printersPath.toNativeUtf16();
      final hPrinters = calloc<IntPtr>();
      try {
        final openRc = _regOpenKeyEx(
          hRoot.value,
          subKey,
          0,
          _keyRead,
          hPrinters,
        );
        if (openRc != 0) {
          return (ok: false, code: openRc, printers: const []);
        }

        try {
          final out = <RawRegistryPrinter>[];
          var index = 0;
          while (true) {
            final name = _enumKeyAt(hPrinters.value, index);
            if (name == null) break;
            out.add((
              name: name,
              driverName: _readValue(hPrinters.value, name, 'Printer Driver'),
              port: _readValue(hPrinters.value, name, 'Port'),
            ));
            index++;
          }
          return (ok: true, code: 0, printers: out);
        } finally {
          _regCloseKey(hPrinters.value);
        }
      } finally {
        calloc.free(subKey);
        calloc.free(hPrinters);
      }
    } finally {
      if (rootOpen) _regCloseKey(hRoot.value);
      calloc.free(machine);
      calloc.free(hRoot);
    }
  }

  /// Το όνομα του υποκλειδιού στη θέση [index], ή `null` όταν τελείωσαν.
  static String? _enumKeyAt(int key, int index) {
    final nameBuf = calloc<Uint16>(_maxKeyNameChars).cast<Utf16>();
    final nameLen = calloc<Uint32>()..value = _maxKeyNameChars;
    try {
      final rc = _regEnumKeyEx(
        key,
        index,
        nameBuf,
        nameLen,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
      );
      if (rc != 0) return null;
      return nameBuf.toDartString();
    } finally {
      calloc.free(nameBuf);
      calloc.free(nameLen);
    }
  }

  /// Μια τιμή κειμένου του εκτυπωτή· κενό όταν λείπει.
  ///
  /// Η αποτυχία είναι σιωπηλή: οδηγός και θύρα είναι συμπληρωματική
  /// πληροφορία και δεν πρέπει να χαλάσουν τη λίστα.
  static String _readValue(int printersKey, String printerName, String value) {
    final sub = printerName.toNativeUtf16();
    final hKey = calloc<IntPtr>();
    var opened = false;
    try {
      if (_regOpenKeyEx(printersKey, sub, 0, _keyRead, hKey) != 0) return '';
      opened = true;

      final valueName = value.toNativeUtf16();
      final len = calloc<Uint32>();
      try {
        // Πρώτη κλήση: πόσα bytes χρειάζονται.
        if (_regQueryValueEx(
              hKey.value,
              valueName,
              nullptr,
              nullptr,
              nullptr,
              len,
            ) !=
            0) {
          return '';
        }
        if (len.value == 0) return '';

        final data = calloc<Uint8>(len.value + 2);
        try {
          if (_regQueryValueEx(
                hKey.value,
                valueName,
                nullptr,
                nullptr,
                data,
                len,
              ) !=
              0) {
            return '';
          }
          return data.cast<Utf16>().toDartString().trim();
        } finally {
          calloc.free(data);
        }
      } finally {
        calloc.free(valueName);
        calloc.free(len);
      }
    } catch (_) {
      return '';
    } finally {
      if (opened) _regCloseKey(hKey.value);
      calloc.free(sub);
      calloc.free(hKey);
    }
  }
}
