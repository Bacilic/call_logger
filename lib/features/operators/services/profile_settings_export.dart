import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_settings_repository.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/profile_settings.dart';

/// Επιλογή θέσης αποθήκευσης — αντικαθίσταται στα τεστ.
typedef ProfileExportSavePathPicker =
    Future<String?> Function(String suggestedFileName);

Future<String?> _pickSavePathWithSystemDialog(String suggestedFileName) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Αντίγραφο των ρυθμίσεών μου',
    fileName: suggestedFileName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
    bytes: Uint8List(0),
  );
  return uri?.toFilePath();
}

/// Αποτέλεσμα εξαγωγής: πού γράφτηκε το αρχείο, ή γιατί δεν γράφτηκε.
class ProfileSettingsExportResult {
  const ProfileSettingsExportResult._({this.path, this.error});

  const ProfileSettingsExportResult.saved(String path) : this._(path: path);
  const ProfileSettingsExportResult.cancelled() : this._();
  const ProfileSettingsExportResult.failed(String error) : this._(error: error);

  final String? path;
  final String? error;

  bool get isSaved => path != null;
}

/// «Αντίγραφο μόνο του προφίλ μου» — το αντίγραφο του απλού χρήστη
/// (κλειδωμένη απόφαση Φάσης 0: το πλήρες αντίγραφο βάσης είναι μόνο του
/// διαχειριστή).
///
/// Γράφει σε αρχείο JSON όλες τις προσωπικές ρυθμίσεις του συνδεδεμένου
/// χρήστη, όπως ζουν στη βάση — ό,τι έχει αποκτήσει ως τώρα. Επιστρέφει τη
/// διαδρομή, ή «ακύρωση»/σφάλμα σε απλά ελληνικά.
Future<ProfileSettingsExportResult> exportActiveOperatorSettings({
  ProfileExportSavePathPicker pickSavePath = _pickSavePathWithSystemDialog,
  DateTime? now,
}) async {
  final operator = CurrentOperator.active;
  if (operator?.id == null) {
    return const ProfileSettingsExportResult.failed(
      'Δεν υπάρχει συνδεδεμένος χρήστης — δεν υπάρχουν προσωπικές ρυθμίσεις '
      'προς αποθήκευση.',
    );
  }

  try {
    final db = await DatabaseHelper.instance.database;
    final settings = await OperatorSettingsRepository(
      db,
    ).getAllForOperator(operator!.id!);

    final safeName = operator.displayName.trim().replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );
    final path = await pickSavePath('ρυθμίσεις_$safeName.json');
    if (path == null || path.trim().isEmpty) {
      return const ProfileSettingsExportResult.cancelled();
    }

    final payload = const JsonEncoder.withIndent('  ').convert({
      'user': operator.displayName,
      'exported_at': (now ?? DateTime.now()).toIso8601String(),
      'settings': settings,
    });
    await File(path.trim()).writeAsString(payload, encoding: utf8);
    return ProfileSettingsExportResult.saved(path.trim());
  } catch (e) {
    return ProfileSettingsExportResult.failed(
      'Η αποθήκευση δεν ολοκληρώθηκε: $e',
    );
  }
}

/// Επιλογή αρχείου προς ανάγνωση — αντικαθίσταται στα τεστ.
typedef ProfileImportOpenPathPicker = Future<String?> Function();

Future<String?> _pickOpenPathWithSystemDialog() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Επαναφορά των ρυθμίσεών μου',
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  return file?.path;
}

/// Αποτέλεσμα εισαγωγής: πόσες ρυθμίσεις επανήλθαν, ή γιατί δεν έγινε.
class ProfileSettingsImportResult {
  const ProfileSettingsImportResult._({this.restoredCount, this.error});

  const ProfileSettingsImportResult.restored(int count)
    : this._(restoredCount: count);
  const ProfileSettingsImportResult.cancelled() : this._();
  const ProfileSettingsImportResult.failed(String error) : this._(error: error);

  final int? restoredCount;
  final String? error;

  bool get isRestored => restoredCount != null;
}

/// Επαναφέρει τις προσωπικές ρυθμίσεις του συνδεδεμένου χρήστη από αρχείο που
/// είχε παραχθεί με την [exportActiveOperatorSettings].
///
/// Οι τιμές γράφονται **στο προφίλ εκείνου που είναι συνδεδεμένος τώρα** — όχι
/// σε αυτόν που αναγράφεται στο αρχείο. Έτσι ο συνάδελφος μπορεί να πάρει τις
/// ρυθμίσεις ενός άλλου ως αφετηρία, χωρίς να πειράξει το προφίλ του.
///
/// Ρυθμίσεις που δεν αναγνωρίζονται (π.χ. από παλαιότερη έκδοση) αγνοούνται
/// σιωπηλά: ένα άγνωστο κλειδί δεν είναι λόγος να χαθεί όλη η επαναφορά.
Future<ProfileSettingsImportResult> importActiveOperatorSettings({
  ProfileImportOpenPathPicker pickOpenPath = _pickOpenPathWithSystemDialog,
}) async {
  final operator = CurrentOperator.active;
  if (operator?.id == null) {
    return const ProfileSettingsImportResult.failed(
      'Δεν υπάρχει συνδεδεμένος χρήστης — δεν ξέρουμε πού να επαναφερθούν οι '
      'ρυθμίσεις.',
    );
  }

  try {
    final path = await pickOpenPath();
    if (path == null || path.trim().isEmpty) {
      return const ProfileSettingsImportResult.cancelled();
    }

    final file = File(path.trim());
    if (!await file.exists()) {
      return const ProfileSettingsImportResult.failed('Το αρχείο δεν βρέθηκε.');
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      return const ProfileSettingsImportResult.failed(
        'Το αρχείο δεν είναι αντίγραφο ρυθμίσεων.',
      );
    }
    final settings = decoded['settings'];
    if (settings is! Map<String, dynamic>) {
      return const ProfileSettingsImportResult.failed(
        'Το αρχείο δεν περιέχει ρυθμίσεις.',
      );
    }

    // Μόνο κλειδιά που η τρέχουσα έκδοση αναγνωρίζει ως προσωπικά.
    final known = {for (final k in ProfileSettingKeys.all) k.key};
    final db = await DatabaseHelper.instance.database;
    final repository = OperatorSettingsRepository(db);
    var restored = 0;
    for (final entry in settings.entries) {
      if (!known.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) {
        await repository.deleteValue(operator!.id!, entry.key);
      } else {
        await repository.setValue(operator!.id!, entry.key, value.toString());
      }
      restored++;
    }
    return ProfileSettingsImportResult.restored(restored);
  } catch (e) {
    return ProfileSettingsImportResult.failed(
      'Η επαναφορά δεν ολοκληρώθηκε: $e',
    );
  }
}
