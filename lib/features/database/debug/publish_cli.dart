import 'dart:convert';
import 'dart:io';

import 'release_publisher_service.dart';

/// Προεπιλεγμένο πρότυπο εντολής δημοσίευσης μέσω τερματικού.
const String kDefaultPublishCliCommandTemplate =
    'dart run tool/publish.dart --folder="{folder}"';

/// Τεκμηρίωση όλων των παραμέτρων CLI (μία γραμμή ανά παράμετρο).
const String kPublishCliParametersHelp =
    '--folder="<διαδρομή>" — υποχρεωτικό· φάκελος ενημερώσεων\n'
    '--rebuild — προαιρετικό· ξαναχτίζει και ξαναδημοσιεύει την τρέχουσα '
    'έκδοση χωρίς νέο αριθμό έκδοσης και χωρίς αλλαγή ιστορικού (αυξάνεται '
    'μόνο ο αριθμός κτισίματος)';

/// Μήνυμα για το καταργημένο `--bump`: το είδος αύξησης (patch/minor) προκύπτει
/// αποκλειστικά από το περιεχόμενο του Unreleased, οπότε το όρισμα δεν είχε
/// ποτέ επίδραση. Ρητή απόρριψη αντί για σιωπηλή ανοχή, ώστε να καθαριστεί και
/// το αποθηκευμένο πρότυπο εντολής.
const String kRemovedBumpArgumentMessage =
    'Το --bump καταργήθηκε: το είδος αύξησης (patch/minor) προκύπτει αυτόματα '
    'από το περιεχόμενο του Unreleased. Αφαιρέστε το από το πρότυπο εντολής.';

/// Επιλογή όταν το Unreleased είναι κενό (καθρέφτης διαλόγου εφαρμογής).
enum EmptyUnreleasedChoice { cancel, installerOnly, rebuild }

/// Ερώτηση διαδραστικού μενού για κενό Unreleased.
typedef EmptyUnreleasedPrompt = EmptyUnreleasedChoice Function();

/// Ορίσματα CLI δημοσίευσης έκδοσης.
class PublishCliArgs {
  const PublishCliArgs({required this.folder, this.rebuild = false});

  final String folder;

  /// Αναδημιουργία τρέχουσας έκδοσης χωρίς νέο αριθμό έκδοσης.
  final bool rebuild;
}

/// Αποτέλεσμα ανάλυσης ορισμάτων CLI.
class PublishCliParseResult {
  const PublishCliParseResult.ok(this.args) : error = null;
  const PublishCliParseResult.error(this.error) : args = null;

  final PublishCliArgs? args;
  final String? error;
}

/// Ανάλυση ορισμάτων: υποχρεωτικό `--folder=`, προαιρετικό `--rebuild`.
PublishCliParseResult parsePublishCliArgs(List<String> arguments) {
  String? folder;
  var rebuild = false;

  for (final raw in arguments) {
    final arg = raw.trim();
    if (arg.isEmpty) continue;
    if (arg == '--rebuild') {
      rebuild = true;
      continue;
    }
    if (arg == '--bump' || arg.startsWith('--bump=')) {
      return const PublishCliParseResult.error(kRemovedBumpArgumentMessage);
    }
    if (arg.startsWith('--folder=')) {
      folder = arg.substring('--folder='.length).trim();
      if (folder.isEmpty) {
        return const PublishCliParseResult.error(
          'Το --folder δεν μπορεί να είναι κενό.',
        );
      }
      continue;
    }
    return PublishCliParseResult.error('Άγνωστο όρισμα: $arg');
  }

  if (folder == null || folder.isEmpty) {
    return const PublishCliParseResult.error('Απαιτείται --folder=<διαδρομή>.');
  }

  return PublishCliParseResult.ok(
    PublishCliArgs(folder: folder, rebuild: rebuild),
  );
}

/// Συμπληρώνει το placeholder `{folder}` στο πρότυπο εντολής.
String buildPublishCliCommand(String template, String folder) {
  return template.replaceAll('{folder}', folder);
}

typedef PublishCliServiceFactory =
    ReleasePublisherService Function({
      required String updateFolderPath,
      void Function(String message)? onProgress,
    });

/// Εκτέλεση δημοσίευσης μέσω CLI.
///
/// Exit codes: `0` επιτυχία, `1` αποτυχία, `2` κενό Unreleased χωρίς
/// επιβεβαίωση / χωρίς διαδραστικό τερματικό.
Future<int> runPublishCli(
  PublishCliArgs args, {
  PublishCliServiceFactory? serviceFactory,
  void Function(String line)? writeLine,
  bool? isInteractive,
  EmptyUnreleasedPrompt? promptEmptyUnreleased,
}) async {
  void log(String line) {
    (writeLine ?? stdout.writeln)(line);
  }

  final interactive = isInteractive ?? stdin.hasTerminal;
  final prompt =
      promptEmptyUnreleased ??
      (() => _defaultPromptEmptyUnreleased(writeLine: log));

  final factory = serviceFactory ?? _defaultServiceFactory;
  final service = factory(updateFolderPath: args.folder, onProgress: log);

  // Ρητή εντολή αναδημιουργίας: δεν εξαρτάται από το Unreleased ούτε ρωτά.
  if (args.rebuild) {
    return _mapPublishResult(await service.rebuildCurrentVersion(), log);
  }

  late final ReleasePublishPreview preview;
  try {
    preview = await service.preparePreview();
  } catch (e) {
    log('Αποτυχία προεπισκόπησης: $e');
    return 1;
  }

  if (!preview.hasUnreleasedEntries) {
    if (!interactive) {
      log(
        'Η ενότητα Unreleased στο changelog είναι κενή. '
        'Τρέξτε από διαδραστικό τερματικό, προσθέστε καταχωρήσεις, '
        'ή ξανατρέξτε με --rebuild για αναδημιουργία χωρίς νέα έκδοση.',
      );
      return 2;
    }

    final choice = prompt();
    switch (choice) {
      case EmptyUnreleasedChoice.cancel:
        log('Ακυρώθηκε λόγω κενού Unreleased.');
        return 2;
      case EmptyUnreleasedChoice.installerOnly:
        return _mapPublishResult(await service.writeInstallerOnly(), log);
      case EmptyUnreleasedChoice.rebuild:
        return _mapPublishResult(await service.rebuildCurrentVersion(), log);
    }
  }

  log(
    'Είδος αύξησης από το Unreleased: ${preview.bumpKind.name} '
    '→ ${preview.nextVersion}.',
  );

  return _mapPublishResult(await service.publish(), log);
}

int _mapPublishResult(
  ReleasePublishResult result,
  void Function(String line) log,
) {
  switch (result.status) {
    case ReleasePublishStatus.success:
      log(result.message ?? 'Επιτυχία.');
      return 0;
    case ReleasePublishStatus.failure:
      final step = result.failedStep ?? 'άγνωστο';
      log('Αποτυχία στο βήμα «$step»: ${result.message ?? ''}');
      return 1;
    case ReleasePublishStatus.emptyUnreleasedWarning:
      log(
        result.message ??
            'Η ενότητα Unreleased στο changelog είναι κενή. '
                'Προσθέστε καταχωρήσεις ή ξανατρέξτε με --rebuild.',
      );
      return 2;
  }
}

EmptyUnreleasedChoice _defaultPromptEmptyUnreleased({
  required void Function(String line) writeLine,
}) {
  writeLine('Το ιστορικό (Unreleased) είναι κενό.');
  writeLine('1) Ακύρωση');
  writeLine('2) Μόνο εγκαταστάτης');
  writeLine('3) Δημιουργία πάραυτα (ίδια έκδοση, νέος αριθμός κτισίματος)');
  writeLine('Επιλογή [1-3]:');
  final raw = stdin.readLineSync()?.trim() ?? '';
  switch (raw) {
    case '2':
      return EmptyUnreleasedChoice.installerOnly;
    case '3':
      return EmptyUnreleasedChoice.rebuild;
    case '1':
    default:
      return EmptyUnreleasedChoice.cancel;
  }
}

PublishCliServiceFactory get _defaultServiceFactory {
  return ({
    required String updateFolderPath,
    void Function(String message)? onProgress,
  }) {
    final projectRoot = Directory.current.path;
    final releaseDir = [
      projectRoot,
      'build',
      'windows',
      'x64',
      'runner',
      'Release',
    ].join(Platform.pathSeparator);

    return ReleasePublisherService(
      projectRoot: projectRoot,
      buildReleaseDirectory: releaseDir,
      updateFolderPath: updateFolderPath,
      clock: DateTime.now,
      onProgress: onProgress,
      processRunner: (exe, args, {workingDirectory, onOutput}) async {
        final process = await Process.start(
          exe,
          args,
          workingDirectory: workingDirectory,
          runInShell: true,
        );
        process.stdout.transform(utf8.decoder).listen((chunk) {
          for (final line in chunk.split(RegExp(r'\r?\n'))) {
            if (line.trim().isEmpty) continue;
            onOutput?.call(line);
          }
        });
        process.stderr.transform(utf8.decoder).listen((chunk) {
          for (final line in chunk.split(RegExp(r'\r?\n'))) {
            if (line.trim().isEmpty) continue;
            onOutput?.call(line);
          }
        });
        return process.exitCode;
      },
    );
  };
}

/// Σημείο εισόδου για `tool/publish.dart` — αναλύει ορίσματα και τρέχει.
Future<int> publishCliMain(List<String> arguments) async {
  final parsed = parsePublishCliArgs(arguments);
  if (parsed.args == null) {
    stderr.writeln(parsed.error ?? 'Μη έγκυρα ορίσματα.');
    stderr.writeln('Χρήση: dart run tool/publish.dart');
    stderr.writeln(kPublishCliParametersHelp);
    return 1;
  }
  return runPublishCli(parsed.args!);
}
