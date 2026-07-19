import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../config/app_config.dart';

/// Αποτέλεσμα ταξινόμησης διαδρομής ως δικτυακής / τοπικής / κοινόχρηστης.
enum NetworkFolderKind {
  /// UNC διαδρομή (`\\server\share\...`).
  networkUnc,

  /// Γράμμα δίσκου που αντιστοιχεί σε mapped network drive.
  networkMappedDrive,

  /// Τοπική διαδρομή κάτω από δημοσιευμένο SMB share.
  localShared,

  /// Καθαρά τοπική διαδρομή χωρίς share.
  localOnly,

  /// Μη-Windows, σφάλμα, timeout ή μη ταξινομήσιμη διαδρομή.
  unknown,
}

/// Αν ο δίσκος με το δοσμένο γράμμα είναι απομακρυσμένος (`true`), τοπικός
/// (`false`) ή άγνωστος (`null`).
typedef DriveTypeResolver = Future<bool?> Function(String driveLetter);

/// Λίστα τοπικών διαδρομών SMB share (μία ανά στοιχείο).
typedef LocalSharesProvider = Future<List<String>> Function();

/// Ταξινομεί διαδρομές φακέλου ενημερώσεων ως δικτυακές ή τοπικές (Windows).
class NetworkFolderClassifier {
  NetworkFolderClassifier({
    required this.driveTypeResolver,
    required this.localSharesProvider,
    bool Function()? isWindows,
  }) : isWindows = isWindows ?? (() => Platform.isWindows);

  /// Προεπιλεγμένη υλοποίηση με FFI GetDriveTypeW και PowerShell Get-SmbShare.
  factory NetworkFolderClassifier.system() {
    return NetworkFolderClassifier(
      driveTypeResolver: _systemDriveTypeResolver,
      localSharesProvider: _systemLocalSharesProvider,
    );
  }

  final DriveTypeResolver driveTypeResolver;
  final LocalSharesProvider localSharesProvider;
  final bool Function() isWindows;

  static final p.Context _win = p.Context(style: p.Style.windows);

  /// Ταξινομεί τη [path] με σταθερή προτεραιότητα (UNC → mapped → share → local).
  Future<NetworkFolderKind> classify(String path) async {
    try {
      if (!isWindows()) return NetworkFolderKind.unknown;

      final trimmed = path.trim();
      if (trimmed.isEmpty) return NetworkFolderKind.unknown;

      if (AppConfig.isUncDatabasePath(trimmed)) {
        return NetworkFolderKind.networkUnc;
      }

      final letter = _windowsDriveLetterFromPath(trimmed);
      if (letter != null) {
        final remote = await driveTypeResolver(letter);
        if (remote == true) {
          return NetworkFolderKind.networkMappedDrive;
        }
      } else {
        // Χωρίς UNC και χωρίς γράμμα δίσκου — δεν μπορούμε να ταξινομήσουμε.
        return NetworkFolderKind.unknown;
      }

      List<String> shares;
      try {
        shares = await localSharesProvider();
      } catch (_) {
        shares = const <String>[];
      }

      final normalizedPath = _normalizeWindowsPath(trimmed);
      for (final share in shares) {
        final normalizedShare = _normalizeWindowsPath(share);
        if (normalizedShare.isEmpty) continue;
        // Αγνόησε διαχειριστικά shares ρίζας δίσκου (`C$` → `C:\`): καλύπτουν
        // όλον τον δίσκο και δεν σημαίνουν πρόσβαση για τους συναδέλφους.
        if (_isBareDriveRoot(normalizedShare)) continue;
        if (normalizedPath == normalizedShare ||
            _win.isWithin(normalizedShare, normalizedPath)) {
          return NetworkFolderKind.localShared;
        }
      }

      return NetworkFolderKind.localOnly;
    } catch (_) {
      return NetworkFolderKind.unknown;
    }
  }

  /// Γράμμα τόμου `A`–`Z` αν η διαδρομή είναι της μορφής `F:\...`, αλλιώς null.
  static String? _windowsDriveLetterFromPath(String path) {
    final t = path.trim().replaceAll('/', r'\');
    if (t.length < 2 || t.codeUnitAt(1) != 0x3A /* ':' */) {
      return null;
    }
    final u = t.codeUnitAt(0);
    if (u >= 0x41 && u <= 0x5a) return String.fromCharCode(u);
    if (u >= 0x61 && u <= 0x7a) {
      return String.fromCharCode(u - 0x20);
    }
    return null;
  }

  /// Γυμνή ρίζα δίσκου (`c:` ή `c:\`) — τυπικά διαχειριστικό share (`C$`).
  static final RegExp _bareDriveRootPattern = RegExp(r'^[a-z]:\\?$');

  static bool _isBareDriveRoot(String normalized) =>
      _bareDriveRootPattern.hasMatch(normalized);

  static String _normalizeWindowsPath(String raw) {
    var s = raw.trim().replaceAll('/', r'\');
    if (s.isEmpty) return '';
    s = _win.normalize(s);
    // Αφαίρεση τελικού separator (εκτός ρίζας δίσκου `C:\`).
    while (s.length > 3 && (s.endsWith(r'\') || s.endsWith('/'))) {
      s = s.substring(0, s.length - 1);
    }
    return s.toLowerCase();
  }

  static Future<bool?> _systemDriveTypeResolver(String driveLetter) async {
    if (!Platform.isWindows) return null;
    final letter = driveLetter.trim().toUpperCase();
    if (letter.length != 1) return null;
    final rootPtr = '$letter:\\'.toPcwstr(allocator: calloc);
    try {
      final t = GetDriveType(rootPtr);
      if (t == DRIVE_REMOTE) return true;
      if (t == DRIVE_UNKNOWN || t == DRIVE_NO_ROOT_DIR) return null;
      return false;
    } catch (_) {
      return null;
    } finally {
      calloc.free(rootPtr);
    }
  }

  static Future<List<String>> _systemLocalSharesProvider() async {
    if (!Platform.isWindows) return const <String>[];
    try {
      final result = await Process.run(
        'powershell',
        const <String>[
          '-NoProfile',
          '-Command',
          // Αποκλεισμός special/διαχειριστικών shares (C$, ADMIN$, IPC$…).
          r'Get-SmbShare | Where-Object { -not $_.Special } | ForEach-Object { $_.Path }',
        ],
      ).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return const <String>[];
      final stdout = result.stdout;
      final text = stdout is String
          ? stdout
          : utf8.decode(stdout as List<int>, allowMalformed: true);
      return const LineSplitter()
          .convert(text)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
    } on TimeoutException {
      return const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }
}
