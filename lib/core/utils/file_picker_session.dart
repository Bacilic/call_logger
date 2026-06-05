import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Αποτέλεσμα guarded κλήσης file picker / native διαλόγου αρχείου.
class FilePickerSessionResult<T> {
  const FilePickerSessionResult._({
    this.value,
    required this.refocusedExisting,
  });

  final T? value;
  final bool refocusedExisting;

  bool get cancelled => value == null && !refocusedExisting;

  static FilePickerSessionResult<T> picked<T>(T? value) =>
      FilePickerSessionResult._(value: value, refocusedExisting: false);

  static FilePickerSessionResult<T> refocused<T>() =>
      const FilePickerSessionResult._(refocusedExisting: true);
}

/// Μία ενεργή συνεδρία file picker· δεύτερο κλικ εστιάζει τον υπάρχοντα διάλογο.
class FilePickerSession {
  FilePickerSession._();

  static bool _active = false;
  static bool _lastRefocusedExisting = false;

  static bool get isActive => _active;

  /// Καταναλώνει και επιστρέφει αν η τελευταία guarded κλήση έκανε refocus.
  static bool takeLastRefocusedExisting() {
    final value = _lastRefocusedExisting;
    _lastRefocusedExisting = false;
    return value;
  }

  static Future<FilePickerSessionResult<T>> run<T>(
    Future<T?> Function() action,
  ) async {
    if (_active) {
      _lastRefocusedExisting = true;
      await focusOpenWindowsFileDialog();
      return FilePickerSessionResult.refocused();
    }

    _lastRefocusedExisting = false;
    _active = true;
    try {
      final value = await action();
      return FilePickerSessionResult.picked(value);
    } finally {
      _active = false;
    }
  }
}

int _focusEnumTargetPid = 0;
HWND? _focusEnumFoundHwnd;

int _focusFileDialogEnumProc(Pointer hwndPtr, int lParam) {
  final hwnd = HWND(hwndPtr);
  if (hwnd.isNull || !IsWindowVisible(hwnd)) {
    return TRUE;
  }

  final pid = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(hwnd, pid);
    if (pid.value != _focusEnumTargetPid) {
      return TRUE;
    }
  } finally {
    calloc.free(pid);
  }

  final classBuffer = calloc<WCHAR>(256);
  try {
    final classNamePtr = classBuffer.cast<Utf16>();
    if (GetClassName(hwnd, PWSTR(classNamePtr), 256).value == 0) {
      return TRUE;
    }
    final className = classNamePtr.toDartString();
    if (className != '#32770') {
      return TRUE;
    }
  } finally {
    calloc.free(classBuffer);
  }

  _focusEnumFoundHwnd = hwnd;
  return FALSE;
}

/// Επαναφέρει και εστιάζει ανοιχτό διάλογο αρχείων των Windows (COMDLG `#32770`).
Future<void> focusOpenWindowsFileDialog() async {
  if (!Platform.isWindows) return;

  _focusEnumTargetPid = GetCurrentProcessId();
  _focusEnumFoundHwnd = null;

  final enumProc = NativeCallable<WNDENUMPROC>.isolateLocal(
    _focusFileDialogEnumProc,
    exceptionalReturn: FALSE,
  );
  try {
    EnumWindows(enumProc.nativeFunction, LPARAM(0));
  } finally {
    enumProc.close();
  }

  final hwnd = _focusEnumFoundHwnd;
  if (hwnd == null || hwnd.isNull) return;

  ShowWindow(hwnd, SW_RESTORE);
  BringWindowToTop(hwnd);
  SetForegroundWindow(hwnd);
}
