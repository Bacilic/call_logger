// Διαχείριση διαδρομών Excel/DB, επικύρωση και συγχρονισμός read/output.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/old_database/lamp_database_provider.dart';
import '../../../core/database/old_database/lamp_old_db_validator.dart';
import '../../../core/providers/lamp_open_settings_intent_provider.dart';
import '../../../core/providers/lamp_read_path_health_provider.dart';
import '../../../core/services/portable_lamp_storage.dart';
import '../../../core/utils/file_picker_session.dart';
import '../../settings/widgets/create_new_database_dialog.dart';
import 'lamp_screen_host.dart';

/// Κατάσταση κουμπιού «ίδια διαδρομή εξόδου» (βελάκι) στον διάλογο ρυθμίσεων.
class LampMatchReadToOutputButtonState {
  const LampMatchReadToOutputButtonState({
    required this.enabled,
    required this.tooltip,
  });

  final bool enabled;
  final String tooltip;
}

LampMatchReadToOutputButtonState computeMatchReadToOutputButtonState({
  required String outputPath,
  required String readPath,
}) {
  final output = outputPath.trim();
  final read = readPath.trim();
  if (output.isEmpty) {
    return const LampMatchReadToOutputButtonState(
      enabled: false,
      tooltip: 'Η διαδρομή της βάσης εξόδου είναι κενή',
    );
  }
  if (LampOldDbValidator.pathsReferToSameFile(output, read)) {
    return const LampMatchReadToOutputButtonState(
      enabled: false,
      tooltip: 'Η διαδρομή της βάσης εξόδου είναι ίδια με τη βάση ανάγνωσης',
    );
  }
  if (LampOldDbValidator.validateDbPathFormat(output) != null) {
    return const LampMatchReadToOutputButtonState(
      enabled: false,
      tooltip: 'Η διαδρομή της βάσης εξόδου δεν είναι έγκυρη (αρχείο .db)',
    );
  }
  return const LampMatchReadToOutputButtonState(
    enabled: true,
    tooltip: 'Ίδια διαδρομή με τη βάση εξόδου',
  );
}

class LampPathController {
  LampPathController({required this.host});

  final LampScreenHost host;

  final excelController = TextEditingController();
  final readDbController = TextEditingController();
  final outputDbController = TextEditingController();

  Timer? pathValidationDebounce;

  void dispose() {
    pathValidationDebounce?.cancel();
    excelController.dispose();
    readDbController.dispose();
    outputDbController.dispose();
  }

  String effectiveReadPathForValidation() {
    var read = readDbController.text.trim();
    final output = outputDbController.text.trim();
    if (read.isEmpty && output.isNotEmpty) {
      read = output;
    }
    return read;
  }

  String? outputPathFormatWarning() =>
      LampOldDbValidator.validateDbPathFormat(outputDbController.text);

  String? readPathFormatWarning() =>
      LampOldDbValidator.validateDbPathFormat(readDbController.text);

  void schedulePathHealthRefresh() {
    pathValidationDebounce?.cancel();
    pathValidationDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!host.mounted) return;
      unawaited(_persistPathsAndRefreshHealth());
    });
  }

  Future<void> _persistPathsAndRefreshHealth() async {
    final read = readDbController.text.trim();
    final output = outputDbController.text.trim();
    final excel = excelController.text.trim();
    final settings = host.shared.settings;
    await settings.setReadPath(read);
    await settings.setOutputPath(output);
    await host.ref.read(lampReadPathHealthProvider.notifier).refresh(
      pathOverride: effectiveReadPathForValidation(),
      outputPathOverride: output,
      excelPathOverride: excel,
    );
    await host.ref.read(lampOutputPathHealthProvider.notifier).refresh(
      pathOverride: output,
    );
    if (host.mounted) {
      host.lampSettingsDialogSetState?.call(() {});
    }
  }

  void notifySettingsDialogFieldsChanged() {
    if (!host.mounted) return;
    schedulePathHealthRefresh();
    host.lampSettingsDialogSetState?.call(() {});
  }

  Future<void> loadPathsFromSettings() async {
    final settings = host.shared.settings;
    final excelPath = await settings.getExcelPath();
    final readRaw = await settings.getReadPathRaw();
    final outRaw = await settings.getOutputPathRaw();
    if (!host.mounted) return;
    excelController.text = excelPath ?? '';
    if (readRaw != null && readRaw.isNotEmpty) {
      readDbController.text = readRaw;
    } else {
      readDbController.text = outRaw ?? '';
    }
    outputDbController.text = outRaw ?? '';
  }

  Future<void> applyPersistedReadAndValidate({
    bool announce = true,
    String source = 'αλλαγή',
    required Future<void> Function() onDbOk,
    required void Function() onDbNotOk,
  }) async {
    var read = readDbController.text.trim();
    final output = outputDbController.text.trim();
    if (read.isEmpty && output.isNotEmpty) {
      read = output;
      readDbController.text = output;
    }
    final settings = host.shared.settings;
    await settings.setReadPath(read);
    await settings.setOutputPath(output);
    await host.ref.read(lampReadPathHealthProvider.notifier).refresh(
      pathOverride: read,
      outputPathOverride: output,
      excelPathOverride: excelController.text.trim(),
    );
    await host.ref.read(lampOutputPathHealthProvider.notifier).refresh(
      pathOverride: output,
    );
    if (!host.mounted) return;
    final result = host.readPathCheck;
    if (result == null) return;
    if (result.status == LampOldDbStatus.ok) {
      await onDbOk();
      if (host.lampSettingsDialogOpen) {
        host.clearLampDialogFeedback();
      }
    } else {
      onDbNotOk();
    }
    if (announce) {
      announceCheck(result, source: source);
    }
  }

  void announceCheck(LampOldDbCheckResult result, {required String source}) {
    if (result.status == LampOldDbStatus.ok ||
        result.status == LampOldDbStatus.pendingCreation) {
      return;
    }
    final prefix = source == 'έναρξη'
        ? 'Λάμπα: '
        : 'Έλεγχος βάσης ($source): ';
    final message = host.lampSettingsDialogOpen
        ? result.userMessageGreek
        : '$prefix${result.userMessageGreek}';
    final isError = result.status != LampOldDbStatus.pathEmpty;
    host.showSnack(
      message,
      isError: isError,
      duration: Duration(seconds: isError ? 8 : 7),
    );
  }

  Future<void> refreshDataAfterReadPathChange({
    required String source,
    bool announce = true,
    required Future<void> Function() onDbOk,
    required void Function() onDbNotOk,
  }) async {
    await LampDatabaseProvider.instance.close();
    await applyPersistedReadAndValidate(
      announce: announce,
      source: source,
      onDbOk: onDbOk,
      onDbNotOk: onDbNotOk,
    );
  }

  Future<void> pickExcel() async {
    final session = await FilePickerSession.run(() async {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['xlsx', 'xls'],
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    });
    if (session.refocusedExisting) return;
    final path = session.value;
    if (path == null) {
      if (host.mounted) {
        host.showSnack('Η επιλογή αρχείου Excel ακυρώθηκε.');
      }
      return;
    }
    excelController.text = path;
    await host.shared.settings.setExcelPath(path);
    if (host.mounted) {
      host.lampSettingsDialogSetState?.call(() {});
      host.showSnack('Ορίστηκε αρχείο Excel: ${p.basename(path)}');
    }
  }

  Future<void> pickReadDatabase({
    required Future<void> Function({required String source}) onPathChanged,
  }) async {
    final session = await FilePickerSession.run(() async {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['db'],
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    });
    if (session.refocusedExisting) return;
    final path = session.value;
    if (path == null) {
      if (host.mounted) {
        host.showSnack('Η επιλογή αρχείου .db (ανάγνωση) ακυρώθηκε.');
      }
      return;
    }
    final portablePath =
        await PortableLampStorage.tryCopyLampDbToPortableDataBase(path);
    readDbController.text = portablePath;
    await host.shared.settings.setReadPath(portablePath);
    if (!host.mounted) return;
    host.lampSettingsDialogSetState?.call(() {});
    host.showSnack('Θα γίνει έλεγχος της βάσης προς ανάγνωση…');
    await onPathChanged(source: 'επιλογή αρχείου ανάγνωσης');
  }

  Future<void> pickDatabaseOutput({
    required Future<void> Function({required String source}) onReadSynced,
  }) async {
    final oldOut = outputDbController.text.trim();
    final path = await pickSqliteDatabaseSavePath(
      initialPathHint: oldOut.isNotEmpty ? oldOut : null,
      dialogTitle: 'Θέση και όνομα βάσης εξόδου (.db) για import Excel',
      defaultSuggestedFileName: 'old_equipment.db',
    );
    if (FilePickerSession.takeLastRefocusedExisting()) return;
    if (path == null) {
      if (host.mounted) {
        host.showSnack('Η αποθήκευση/προορισμός αρχείου εξόδου ακυρώθηκε.');
      }
      return;
    }
    final validationError = validateNewDatabaseSavePath(path);
    if (validationError != null) {
      if (host.mounted) {
        host.showSnack(validationError, isError: true);
      }
      return;
    }
    final portablePath =
        await PortableLampStorage.tryCopyLampDbToPortableDataBase(path);
    outputDbController.text = portablePath;
    await host.shared.settings.setOutputPath(portablePath);
    final readT = readDbController.text.trim();
    if (readT.isEmpty || (oldOut.isNotEmpty && readT == oldOut)) {
      readDbController.text = portablePath;
      await host.shared.settings.setReadPath(portablePath);
      if (host.mounted) {
        host.showSnack(
          'Η διαδρομή εξόδου ενημερώθηκε. Η «ανάγνωση» συγχρονίστηκε (ίδιο αρχείο).',
        );
        host.lampSettingsDialogSetState?.call(() {});
      }
      await onReadSynced(source: 'αλλαγή αρχείου εξόδου');
    } else {
      if (host.mounted) {
        host.showSnack(
          'Η διαδρομή εξόδου (δημιουργίας) ενημερώθηκε. Η βάση προς «ανάγνωση» παρέμεινε ξεχωριστή.',
        );
        host.lampSettingsDialogSetState?.call(() {});
      }
    }
  }

  Future<void> matchReadToOutput({
    required Future<void> Function() onDbOk,
    required void Function() onDbNotOk,
  }) async {
    final output = outputDbController.text.trim();
    final read = readDbController.text.trim();
    if (output.isEmpty) return;

    if (read.isNotEmpty &&
        !LampOldDbValidator.pathsReferToSameFile(read, output)) {
      final confirmed = await showDialog<bool>(
        context: host.context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Αντικατάσταση διαδρομής ανάγνωσης'),
            content: Text(
              'Η βάση ανάγνωσης δείχνει σε διαφορετικό αρχείο '
              '(${p.basename(read)}). Θέλετε να αντικατασταθεί με τη διαδρομή '
              'εξόδου (${p.basename(output)});',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Ακύρωση'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Αντικατάσταση'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }

    readDbController.text = output;
    if (!host.mounted) return;
    host.lampSettingsDialogSetState?.call(() {});
    await applyPersistedReadAndValidate(
      announce: false,
      source: 'ευθυγράμμιση ανάγνωσης',
      onDbOk: onDbOk,
      onDbNotOk: onDbNotOk,
    );
    if (host.mounted) {
      host.showSnack('Η βάση ανάγνωσης ευθυγραμμίστηκε με τη διαδρομή εξόδου.');
    }
  }
}

class LampPathFormatWarningBanner extends StatelessWidget {
  const LampPathFormatWarningBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LampPathRow extends StatelessWidget {
  const LampPathRow({
    super.key,
    required this.controller,
    required this.label,
    required this.onPick,
    this.onChanged,
    this.infoTooltip,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;
  final VoidCallback? onChanged;
  final String? infoTooltip;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (infoTooltip != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 4),
            child: Tooltip(
              waitDuration: const Duration(milliseconds: 300),
              showDuration: const Duration(seconds: 8),
              message: infoTooltip,
              child: Icon(
                Icons.info_outline,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged == null ? null : (_) => onChanged!(),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              hintText:
                  'Μπορείτε και επικόλληση (paste) — ο έλεγχος γίνεται αυτόματα',
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.folder_open),
          label: const Text('Επιλογή'),
        ),
      ],
    );
  }
}

class LampPathCheckPanel extends StatelessWidget {
  const LampPathCheckPanel({
    super.key,
    required this.pathCheck,
    required this.pathController,
    this.pendingMessage,
    this.emptyMessage =
        'Δεν έχει τρέξει ακόμη έλεγχος — γίνεται αυτόματα μόλις οριστεί διαδρομή.',
  });

  final LampOldDbCheckResult? pathCheck;
  final TextEditingController pathController;
  final String? pendingMessage;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final r = pathCheck;
    if (r == null) {
      return Text(
        emptyMessage,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final Color? bg;
    final IconData icon;
    if (r.status == LampOldDbStatus.ok ||
        r.status == LampOldDbStatus.outputWillUpdate) {
      bg = scheme.primaryContainer.withValues(alpha: 0.45);
      icon = Icons.check_circle_outline;
    } else if (r.status == LampOldDbStatus.pathEmpty ||
        r.status == LampOldDbStatus.pendingCreation ||
        r.status == LampOldDbStatus.outputPendingCreation) {
      bg = scheme.surfaceContainerHighest;
      icon = Icons.info_outline;
    } else {
      bg = scheme.errorContainer.withValues(alpha: 0.55);
      icon = Icons.error_outline;
    }
    final showMessage = r.status != LampOldDbStatus.ok;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurface),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pathController.text.isNotEmpty)
                    Text(
                      p.basename(pathController.text),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (showMessage) ...[
                    if (pathController.text.isNotEmpty &&
                        r.status != LampOldDbStatus.pendingCreation &&
                        r.status != LampOldDbStatus.outputPendingCreation)
                      const SizedBox(height: 4),
                    Text(
                      pendingMessage ?? r.userMessageGreek,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Πίνακας ελέγχου διαδρομής ανάγνωσης (συμβατότητα).
class LampReadPathCheckPanel extends StatelessWidget {
  const LampReadPathCheckPanel({
    super.key,
    required this.readPathCheck,
    required this.readDbController,
  });

  final LampOldDbCheckResult? readPathCheck;
  final TextEditingController readDbController;

  @override
  Widget build(BuildContext context) {
    return LampPathCheckPanel(
      pathCheck: readPathCheck,
      pathController: readDbController,
    );
  }
}

class LampSearchTabReadPathBanner extends ConsumerWidget {
  const LampSearchTabReadPathBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(lampReadPathHealthProvider).value;
    if (!lampReadPathNeedsAttention(check)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final IconData icon;
    if (check!.status == LampOldDbStatus.pathEmpty ||
        check.status == LampOldDbStatus.pendingCreation) {
      bg = scheme.surfaceContainerHighest;
      icon = Icons.info_outline;
    } else {
      bg = scheme.errorContainer.withValues(alpha: 0.55);
      icon = Icons.error_outline;
    }
    final bannerTitle = check.status == LampOldDbStatus.pendingCreation
        ? 'Η βάση δεν έχει δημιουργηθεί ακόμα'
        : 'Η παλιά βάση δεν είναι έτοιμη για αναζήτηση';
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: scheme.onSurface),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bannerTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    check.userMessageGreek,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () {
                ref.read(lampOpenSettingsRequestProvider.notifier).request();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Ρυθμίσεις διαδρομών'),
            ),
          ],
        ),
      ),
    );
  }
}
