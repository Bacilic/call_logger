// Εισαγωγή Excel σε βάση .db: έλεγχοι εισόδου και ενημέρωση διαδρομών.
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import 'lamp_path_management.dart';
import 'lamp_screen_host.dart';

class LampImportController {
  LampImportController({
    required this.host,
    required this.path,
  });

  final LampScreenHost host;
  final LampPathController path;

  bool importing = false;

  String? excelImportDisabledReason() {
    final excelEmpty = path.excelController.text.trim().isEmpty;
    final outEmpty = path.outputDbController.text.trim().isEmpty;
    if (excelEmpty && outEmpty) {
      return 'Λείπει το Excel και διαδρομή του αρχείου εξόδου .db';
    }
    if (excelEmpty) {
      return 'Λείπει το αρχείο Excel';
    }
    if (outEmpty) {
      return 'Δεν έχει οριστεί διαδρομή εξόδου';
    }
    final outputFormatError = LampOldDbValidator.validateDbPathFormat(
      path.outputDbController.text,
    );
    if (outputFormatError != null) {
      return outputFormatError;
    }
    return null;
  }

  Widget excelImportButton({
    required VoidCallback onImport,
    required String? message,
  }) {
    final blockReason = excelImportDisabledReason();
    final enabled = !importing && blockReason == null;
    final button = FilledButton.icon(
      onPressed: enabled ? onImport : null,
      icon: const Icon(Icons.play_arrow),
      label: const Text('Δημιουργία/ενημέρωση βάσης από Excel'),
    );
    final tooltipMessage =
        importing ? 'Εκτελείται εισαγωγή Excel…' : blockReason;
    if (enabled || tooltipMessage == null) {
      return button;
    }
    return Tooltip(
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 5),
      message: tooltipMessage,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {},
          child: IgnorePointer(child: button),
        ),
      ),
    );
  }

  Future<String?> runImport({
    required void Function() onImportStart,
    required void Function(String message) onImportSuccess,
    required Future<void> Function() afterImportValidate,
    required Future<void> Function() onImportFailureReload,
  }) async {
    final excelPath = path.excelController.text.trim();
    final outPath = path.outputDbController.text.trim();
    final blockReason = excelImportDisabledReason();
    if (blockReason != null) {
      host.showSnack(blockReason, isError: true);
      return blockReason;
    }

    final settings = host.shared.settings;
    await settings.setExcelPath(excelPath);
    await settings.setOutputPath(outPath);
    await LampDatabaseProvider.instance.close();
    importing = true;
    onImportStart();
    host.lampSettingsDialogSetState?.call(() {});

    try {
      host.showSnack(
        'Ξεκίνησε η εισαγωγή Excel · περιμένετε…',
        duration: const Duration(seconds: 3),
      );
      final result = await host.shared.importer.importExcel(
        excelPath: excelPath,
        databasePath: outPath,
        onProgress: (_) {
          if (!host.mounted) return;
        },
      );
      if (!host.mounted) return null;
      await settings.setOutputAndReadFromImportResult(result.databasePath);
      path.readDbController.text = result.databasePath;
      path.outputDbController.text = result.databasePath;
      final successMessage =
          'Ολοκληρώθηκε η βάση ${p.basename(result.databasePath)}. Προβλήματα ETL: ${result.issueCount}. '
          'Η αποθηκευμένη διαδρομή «ανάγνωση» ευθυγραμμίστηκε με το .db εξόδου (ίδιο αρχείο).';
      onImportSuccess(successMessage);
      host.lampSettingsDialogSetState?.call(() {});
      host.showSnack(
        'Η εισαγωγή τελείωσε. Έγινε επανασύνδεση· γίνεται έλεγχος αρχείου…',
        duration: const Duration(seconds: 4),
      );
      await afterImportValidate();
      return null;
    } catch (e) {
      if (!host.mounted) return 'Η εισαγωγή Excel απέτυχε.';
      host.showSnack(
        'Η εισαγωγή Excel απέτυχε:\n\n$e',
        isError: true,
      );
      await onImportFailureReload();
      return 'Η εισαγωγή Excel απέτυχε.';
    } finally {
      if (host.mounted) {
        importing = false;
        host.lampSettingsDialogSetState?.call(() {});
        host.notifyState();
      }
    }
  }
}
