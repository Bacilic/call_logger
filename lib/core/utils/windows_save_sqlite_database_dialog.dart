import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Φίλτρο COMDLG32: εμφανίζεται ως «SQLite Database (*.db)» στο «Αποθήκευση ως».
const String kSqliteDatabaseSaveFilter =
    'SQLite Database (*.db)\x00*.db\x00\x00';

class _SaveSqliteDatabaseArgs {
  _SaveSqliteDatabaseArgs({
    required this.sendPort,
    required this.dialogTitle,
    required this.fileName,
    this.initialDirectory,
  });

  final SendPort sendPort;
  final String dialogTitle;
  final String fileName;
  final String? initialDirectory;
}

/// Native διάλογος «Αποθήκευση ως» των Windows με ετικέτα SQLite Database.
Future<String?> showWindowsSaveSqliteDatabasePath({
  required String dialogTitle,
  required String fileName,
  String? initialDirectory,
}) async {
  if (!Platform.isWindows) return null;

  final port = ReceivePort();
  await Isolate.spawn(
    _saveSqliteDatabaseIsolate,
    _SaveSqliteDatabaseArgs(
      sendPort: port.sendPort,
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
    ),
  );
  final result = await port.first;
  return result as String?;
}

void _saveSqliteDatabaseIsolate(_SaveSqliteDatabaseArgs args) {
  args.sendPort.send(
    _runSaveSqliteDatabaseDialog(
      dialogTitle: args.dialogTitle,
      fileName: args.fileName,
      initialDirectory: args.initialDirectory,
    ),
  );
}

String? _runSaveSqliteDatabaseDialog({
  required String dialogTitle,
  required String fileName,
  String? initialDirectory,
}) {
  final arena = Arena();
  try {
    const maxFileChars = 32768;
    final ofn = arena.allocate<OPENFILENAME>(sizeOf<OPENFILENAME>());
    ofn.ref
      ..lStructSize = sizeOf<OPENFILENAME>()
      ..lpstrFilter = kSqliteDatabaseSaveFilter.toPwstr(allocator: arena)
      ..lpstrFile = arena.pwstrBuffer(maxFileChars)
      ..nMaxFile = maxFileChars
      ..lpstrTitle = dialogTitle.toPwstr(allocator: arena)
      ..lpstrDefExt = 'db'.toPwstr(allocator: arena)
      ..Flags = OFN_EXPLORER |
          OFN_HIDEREADONLY |
          OFN_NOCHANGEDIR |
          OFN_OVERWRITEPROMPT;

    final initial = initialDirectory?.trim() ?? '';
    if (initial.isNotEmpty) {
      ofn.ref.lpstrInitialDir = initial.toPwstr(allocator: arena);
    }

    final safeName = fileName.substring(
      0,
      fileName.length.clamp(0, maxFileChars - 1),
    );
    ofn.ref.lpstrFile.setString(safeName);

    final hwnd = FindWindow(
      arena.pcwstr('FLUTTER_RUNNER_WIN32_WINDOW'),
      null,
    ).value;
    if (!hwnd.isNull) {
      ofn.ref.hwndOwner = hwnd;
    }

    if (!GetSaveFileName(ofn)) {
      return null;
    }

    return ofn.ref.lpstrFile.toDartString().trim();
  } finally {
    arena.releaseAll();
  }
}
