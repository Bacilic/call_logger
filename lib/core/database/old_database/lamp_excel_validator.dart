import 'dart:io';

import 'package:path/path.dart' as p;

/// Αποτέλεσμα ελέγχου αρχείου Excel (πηγή εισαγωγής Λάμπας).
enum LampExcelStatus {
  pathEmpty,
  missing,
  notAFile,
  wrongExtension,
  empty,
  locked,
  ok,
}

class LampExcelCheckResult {
  const LampExcelCheckResult(
    this.status, {
    this.technicalDetail,
  });

  final LampExcelStatus status;
  final String? technicalDetail;

  String get userMessageGreek {
    switch (status) {
      case LampExcelStatus.pathEmpty:
        return 'Δεν έχει οριστεί αρχείο Excel.';
      case LampExcelStatus.missing:
        return 'Το αρχείο Excel δεν βρέθηκε στη δίσκο. Ελέγξτε τη διαδρομή '
            '(δίκτυο, αφαιρούμενο δίσκο) ή επιλέξτε ξανά το αρχείο.';
      case LampExcelStatus.notAFile:
        return 'Η διαδρομή Excel δεν δείχνει σε αρχείο — φαίνεται φάκελος.';
      case LampExcelStatus.wrongExtension:
        return 'Η κατάληξη του αρχείου Excel πρέπει να είναι .xlsx ή .xls.';
      case LampExcelStatus.empty:
        return 'Το αρχείο Excel είναι άδειο (0 byte). Επιλέξτε έγκυρο αρχείο.';
      case LampExcelStatus.locked:
        return 'Το αρχείο Excel είναι ανοιχτό ή κλειδωμένο από άλλη εφαρμογή '
            '(π.χ. ανοιχτό στο Excel) — κλείστε το και δοκιμάστε ξανά.';
      case LampExcelStatus.ok:
        return 'Το αρχείο Excel είναι προσπελάσιμο και έτοιμο για εισαγωγή.';
    }
  }
}

/// Επαλήθευση πηγής Excel πριν από εισαγωγή ή εμφάνιση κατάστασης.
class LampExcelValidator {
  const LampExcelValidator();

  Future<LampExcelCheckResult> validateExcelSource(String? rawPath) async {
    final path = rawPath?.trim() ?? '';
    if (path.isEmpty) {
      return const LampExcelCheckResult(LampExcelStatus.pathEmpty);
    }

    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.notFound) {
      return const LampExcelCheckResult(LampExcelStatus.missing);
    }
    if (entity == FileSystemEntityType.directory) {
      return const LampExcelCheckResult(LampExcelStatus.notAFile);
    }

    final ext = p.extension(path).toLowerCase();
    if (ext != '.xlsx' && ext != '.xls') {
      return LampExcelCheckResult(
        LampExcelStatus.wrongExtension,
        technicalDetail: ext.isEmpty ? '(χωρίς κατάληξη)' : ext,
      );
    }

    final file = File(path);
    final stat = await file.stat();
    if (stat.size == 0) {
      return const LampExcelCheckResult(LampExcelStatus.empty);
    }

    // Best-effort: στα Windows συχνά επιτρέπεται shared-read ακόμη κι αν το Excel
    // έχει το αρχείο ανοιχτό — δοκιμάζουμε και αποκλειστικό κλείδωμα.
    try {
      final handle = await file.open(mode: FileMode.read);
      try {
        await handle.lock(FileLock.exclusive);
        await handle.unlock();
      } on FileSystemException catch (e) {
        return LampExcelCheckResult(
          LampExcelStatus.locked,
          technicalDetail: e.message,
        );
      } finally {
        await handle.close();
      }
    } on FileSystemException catch (e) {
      return LampExcelCheckResult(
        LampExcelStatus.locked,
        technicalDetail: e.message,
      );
    }

    return const LampExcelCheckResult(LampExcelStatus.ok);
  }
}

/// True όταν ο έλεγχος Excel μπλοκάρει το κουμπί import.
bool lampExcelPathBlocksImport(LampExcelCheckResult result) {
  switch (result.status) {
    case LampExcelStatus.ok:
    case LampExcelStatus.pathEmpty:
      return false;
    case LampExcelStatus.missing:
    case LampExcelStatus.notAFile:
    case LampExcelStatus.wrongExtension:
    case LampExcelStatus.empty:
    case LampExcelStatus.locked:
      return true;
  }
}
