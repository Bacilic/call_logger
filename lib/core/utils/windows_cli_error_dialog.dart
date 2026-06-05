import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Εμφανίζει native διάλογο σφάλματος Windows για άκυρες παραμέτρους CLI.
void showWindowsCliErrorDialog(String message) {
  if (!Platform.isWindows) {
    stderr.writeln(message);
    return;
  }

  using((arena) {
    MessageBox(
      null,
      arena.pcwstr(message),
      arena.pcwstr('Καταγραφή Κλήσεων'),
      MB_OK | MB_ICONERROR,
    );
  });
}
