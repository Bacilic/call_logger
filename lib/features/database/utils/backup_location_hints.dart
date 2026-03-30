import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Τμήμα κειμένου για εμφάνιση με [Text.rich] (έντονα γράμματα τόμου κ.λπ.).
class BackupCaptionSegment {
  const BackupCaptionSegment(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

/// Υποδείξεις τόμων (drives) για προορισμό αντιγράφων ασφαλείας — μόνο Windows.
class BackupLocationHints {
  BackupLocationHints._();

  /// Γράμμα τόμου `A`–`Z` αν η διαδρομή είναι της μορφής `F:\...`, αλλιώς null (π.χ. UNC).
  static String? windowsDriveLetterFromPath(String path) {
    final t = path.trim().replaceAll('/', '\\');
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

  /// Το γράμμα τόμου από ετικέτα όπως `D` ή `F (USB)`.
  static String? leadingDriveLetterFromLabel(String label) {
    if (label.isEmpty) return null;
    final c = label.codeUnitAt(0);
    if (c >= 0x41 && c <= 0x5a) return String.fromCharCode(c);
    if (c >= 0x61 && c <= 0x7a) {
      return String.fromCharCode(c - 0x20);
    }
    return null;
  }

  static List<String> _withoutDatabaseDrive(
    List<String> driveLabels,
    String? databaseDriveLetter,
  ) {
    if (databaseDriveLetter == null) return List<String>.from(driveLabels);
    return driveLabels
        .where(
          (l) => leadingDriveLetterFromLabel(l) != databaseDriveLetter,
        )
        .toList();
  }

  /// Επιστρέφει ετικέτες τόμων με γράμμα (π.χ. `D`, `F (USB)`, `H (δικτυακός)`).
  /// Εξαιρούνται CD/DVD και άκυροι τόμοι. Κενή λίστα εκτός Windows.
  static List<String> eligibleWindowsBackupDriveLabels() {
    if (!Platform.isWindows) return [];

    final mask = GetLogicalDrives();
    final out = <String>[];

    for (var i = 0; i < 26; i++) {
      if ((mask & (1 << i)) == 0) continue;
      final letter = String.fromCharCode(0x41 + i);
      final rootPtr = '$letter:\\'.toNativeUtf16(allocator: calloc);
      try {
        final t = GetDriveType(rootPtr);
        if (t == DRIVE_CDROM ||
            t == DRIVE_UNKNOWN ||
            t == DRIVE_NO_ROOT_DIR) {
          continue;
        }
        if (t == DRIVE_REMOVABLE) {
          out.add('$letter (USB)');
        } else if (t == DRIVE_REMOTE) {
          out.add('$letter (δικτυακός)');
        } else {
          out.add(letter);
        }
      } finally {
        calloc.free(rootPtr);
      }
    }
    return out;
  }

  /// Παράγραφος ως τμήματα: έντονο μόνο το γράμμα τόμου (π.χ. C, F σε «F (USB)»).
  /// Στον τόμο της βάσης **χωρίς** `:` μετά το γράμμα.
  static List<BackupCaptionSegment> composeLocationCaptionSegments({
    required List<String> driveLabels,
    required String configuredDatabasePath,
  }) {
    final db = configuredDatabasePath.trim();
    final dbLetter = db.isEmpty ? null : windowsDriveLetterFromPath(db);
    final filtered = _withoutDatabaseDrive(driveLabels, dbLetter);

    final segs = <BackupCaptionSegment>[];
    void add(String text, {bool bold = false}) {
      segs.add(BackupCaptionSegment(text, bold: bold));
    }

    if (filtered.isNotEmpty) {
      add(
        'Προτείνεται αποθήκευση αντιγράφων ασφαλείας στους δίσκους: ',
      );
      _addJoinedDriveLabels(segs, filtered);
      add('. ');
    } else if (driveLabels.isNotEmpty &&
        dbLetter != null &&
        driveLabels.every(
          (l) => leadingDriveLetterFromLabel(l) == dbLetter,
        )) {
      add(
        'Προτείνεται αποθήκευση αντιγράφων ασφαλείας σε άλλο τόμο ή '
        'δικτυακό φάκελο — δεν εντοπίστηκε άλλος τόμος πέραν του τόμου της βάσης. ',
      );
    } else if (driveLabels.isNotEmpty) {
      add(
        'Προτείνεται αποθήκευση αντιγράφων ασφαλείας στους δίσκους: ',
      );
      _addJoinedDriveLabels(segs, driveLabels);
      add('. ');
    } else {
      add(
        'Προτείνεται αποθήκευση αντιγράφων ασφαλείας σε τόμους εκτός του '
        'συστήματος, π.χ. ',
      );
      _addLabelWithBoldLetter(segs, 'D');
      add(', ');
      _addLabelWithBoldLetter(segs, 'E');
      add(' κ.λπ. ');
    }

    segs.addAll(_databaseStorageSegments(db, dbLetter));
    return segs;
  }

  static void _addJoinedDriveLabels(
    List<BackupCaptionSegment> segs,
    List<String> labels,
  ) {
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) {
        segs.add(const BackupCaptionSegment(', '));
      }
      _addLabelWithBoldLetter(segs, labels[i]);
    }
  }

  /// Έντονο το αρχικό γράμμα τόμου· το υπόλοιπο της ετικέτας (π.χ. ` (USB)`) κανονικό.
  static void _addLabelWithBoldLetter(
    List<BackupCaptionSegment> segs,
    String label,
  ) {
    final letter = leadingDriveLetterFromLabel(label);
    if (letter != null &&
        label.startsWith(letter) &&
        label.length > letter.length &&
        label.codeUnitAt(letter.length) == 0x20 /* space */) {
      segs.add(BackupCaptionSegment(letter, bold: true));
      segs.add(BackupCaptionSegment(label.substring(letter.length)));
      return;
    }
    if (letter != null && label == letter) {
      segs.add(BackupCaptionSegment(letter, bold: true));
      return;
    }
    segs.add(BackupCaptionSegment(label));
  }

  static List<BackupCaptionSegment> _databaseStorageSegments(
    String configuredPath,
    String? letterFromPath,
  ) {
    final db = configuredPath.trim();
    if (db.isEmpty) {
      return [
        const BackupCaptionSegment(
          'Η βάση δεδομένων δεν έχει οριστεί πλήρης διαδρομή στις ρυθμίσεις.',
        ),
      ];
    }
    final norm = db.replaceAll('/', '\\');
    if (norm.startsWith(r'\\')) {
      return [
        const BackupCaptionSegment(
          'Η βάση δεδομένων είναι αποθηκευμένη στη δικτυακή διαδρομή ',
        ),
        BackupCaptionSegment(db),
        const BackupCaptionSegment('.'),
      ];
    }
    if (letterFromPath != null) {
      return [
        const BackupCaptionSegment(
          'Η βάση δεδομένων είναι αποθηκευμένη στον δίσκο ',
        ),
        BackupCaptionSegment(letterFromPath, bold: true),
        const BackupCaptionSegment('.'),
      ];
    }
    return [
      const BackupCaptionSegment(
        'Η βάση δεδομένων είναι αποθηκευμένη στη διαδρομή ',
      ),
      BackupCaptionSegment(db),
      const BackupCaptionSegment('.'),
    ];
  }
}
