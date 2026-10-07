import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/crash_log_service.dart';
import '../../core/services/station_name.dart';
import '../../core/utils/file_picker_session.dart';
import '../../core/utils/user_facing_error_messages.dart';
import 'models/diagnostics_export_options.dart';
import 'models/windows_events.dart';
import 'services/diagnostics_report_builder.dart';
import 'services/log_archive_reader.dart';
import 'services/windows_event_log_reader.dart';
import 'widgets/diagnostics_export_dialog.dart';

/// Επιλογή θέσης αποθήκευσης — αντικαθίσταται στα τεστ.
typedef DiagnosticsSavePathPicker =
    Future<String?> Function(
      String suggestedFileName,
      String? initialDirectory,
    );

Future<String?> _pickWithSystemDialog(
  String suggestedFileName,
  String? initialDirectory,
) async {
  final uri = (await FilePickerSession.run(
    () async => FilePicker.saveFile(
      dialogTitle: 'Εξαγωγή διαγνωστικών',
      fileName: suggestedFileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: const ['md'],
      bytes: Uint8List(0),
    ),
  )).value;
  return uri?.toFilePath();
}

/// Η Επιφάνεια εργασίας του χρήστη, αν υπάρχει εκεί που την περιμένουμε.
String? _desktopDirectory() {
  final profile = Platform.environment['USERPROFILE'];
  if (profile == null || profile.isEmpty) return null;
  for (final candidate in [
    p.join(profile, 'Desktop'),
    p.join(profile, 'OneDrive', 'Desktop'),
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Τα φίλτρα για «αυτό το περιστατικό»: η ημέρα του, ο υπολογιστής μας, όλο
/// το περιεχόμενο — ώστε να φαίνεται και τι έγινε γύρω του.
DiagnosticsExportOptions incidentPreset(DateTime occurredAt) =>
    DiagnosticsExportOptions(
      from: occurredAt,
      to: occurredAt,
      stations: {StationName.current},
      contents: {...DiagnosticsContent.values},
      windows: WindowsEventsOptions(levels: {...WindowsEventLevel.selectable}),
    );

/// «Εξαγωγή διαγνωστικών»: διαβάζει τα αρχεία, ρωτά φίλτρα και θέση, γράφει
/// ένα αρχείο markdown και λέει στον χρήστη πού.
///
/// Τα μηνύματα βγαίνουν από τον messenger που κρατήθηκε **πριν** από κάθε
/// αναμονή: οι διάλογοι κρατούν αρκετά ώστε ο `context` να μην ισχύει πια.
Future<void> runDiagnosticsExport({
  required BuildContext context,
  required String logsDirectory,
  required String databasePath,
  DiagnosticsExportOptions? preset,
  DiagnosticsSavePathPicker pickSavePath = _pickWithSystemDialog,
  Future<WindowsEventsReport> Function(WindowsEventsRequest request)
      readWindows =
      _readWindowsEvents,
  DateTime Function() now = DateTime.now,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final LogArchive archive;
  try {
    archive = await readLogArchive(logsDirectory);
  } on Exception catch (error) {
    say(
      'Δεν διαβάστηκαν τα αρχεία καταγραφής: '
      '${humanizeUserFacingError(error)}',
    );
    return;
  }
  if (!context.mounted) return;

  final today = now();
  final station = StationName.current;
  final options = await DiagnosticsExportDialog.show(
    context,
    stations: archive.stations,
    thisStation: station,
    oldestDay: archive.oldestDay,
    today: today,
    initial: preset,
  );
  if (options == null) return;

  String two(int value) => value.toString().padLeft(2, '0');
  final stamp = '${today.year}-${two(today.month)}-${two(today.day)}';
  final who = options.stations.length == 1
      ? StationName.fileSafeOf(options.stations.single)
      : 'πολλοί';
  final String? path;
  try {
    path = await pickSavePath(
      'Διαγνωστικά_${who}_$stamp.md',
      _desktopDirectory(),
    );
  } on Exception catch (error) {
    say(
      'Δεν άνοιξε ο διάλογος αποθήκευσης: '
      '${humanizeUserFacingError(error)}',
    );
    return;
  }
  if (path == null || path.trim().isEmpty) return;

  // Ακριβώς το όνομα που διάλεξε ο χρήστης: ο διάλογος των Windows έχει ήδη
  // δημιουργήσει εκεί ένα άδειο αρχείο, και μια δική μας κατάληξη θα άφηνε
  // δίπλα του δεύτερο, ορφανό.
  final target = path.trim();
  WindowsEventsReport? windows;
  final windowsOptions = options.windows;
  if (windowsOptions != null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Διαβάζονται τα συμβάντα των Windows…')),
    );
    final (from, to) = options.windowsPeriod(today);
    windows = await readWindows(
      WindowsEventsRequest(
        station: station,
        from: from,
        to: to,
        levels: windowsOptions.levels,
        appExecutable: currentExecutableName(),
      ),
    );
    messenger.hideCurrentSnackBar();
  }
  try {
    final report = buildDiagnosticsReport(
      archive: archive,
      options: options,
      windows: windows,
      context: DiagnosticsContext(
        exportedAt: today,
        station: station,
        appVersion: CrashLogService.instanceOrNull?.appVersion ?? '',
        windowsVersion: Platform.operatingSystemVersion,
        databasePath: databasePath,
      ),
    );
    await File(target).writeAsString(report, encoding: utf8, flush: true);
  } on Exception catch (error) {
    say('Η εξαγωγή δεν ολοκληρώθηκε: ${humanizeUserFacingError(error)}');
    return;
  }
  say('Τα διαγνωστικά αποθηκεύτηκαν: $target');
}

Future<WindowsEventsReport> _readWindowsEvents(WindowsEventsRequest request) =>
    readWindowsEvents(request);
