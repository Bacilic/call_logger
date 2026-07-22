import 'dart:convert';
import 'dart:io';

import 'release_publisher_service.dart';

/// Προεπιλεγμένο πρότυπο εντολής δημοσίευσης μέσω τερματικού.
const String kDefaultPublishCliCommandTemplate =
    'dart run tool/publish.dart --bump={bump} --folder="{folder}"';

/// Τεκμηρίωση όλων των παραμέτρων CLI (μία γραμμή ανά παράμετρο).
const String kPublishCliParametersHelp =
    '--bump=patch|minor — υποχρεωτικό· είδος αύξησης έκδοσης\n'
    '--folder="<διαδρομή>" — υποχρεωτικό· φάκελος ενημερώσεων\n'
    '--allow-empty — προαιρετικό· μεταγλωττίζει και δημοσιεύει χωρίς έλεγχο '
    'μη δημοσιευμένων αλλαγών, παρακάμπτοντας το ερώτημα κενού Unreleased';

/// Επιλογή όταν το Unreleased είναι κενό (καθρέφτης διαλόγου εφαρμογής).
enum EmptyUnreleasedChoice { cancel, installerOnly, publishAnyway }

/// Ερώτηση διαδραστικού μενού για κενό Unreleased.
typedef EmptyUnreleasedPrompt = EmptyUnreleasedChoice Function();

/// Ορίσματα CLI δημοσίευσης έκδοσης.
class PublishCliArgs {
  const PublishCliArgs({
    required this.bumpKind,
    required this.folder,
    this.allowEmpty = false,
  });

  final VersionBumpKind bumpKind;
  final String folder;
  final bool allowEmpty;
}

/// Αποτέλεσμα ανάλυσης ορισμάτων CLI.
class PublishCliParseResult {
  const PublishCliParseResult.ok(this.args) : error = null;
  const PublishCliParseResult.error(this.error) : args = null;

  final PublishCliArgs? args;
  final String? error;
}

/// Ανάλυση ορισμάτων `--bump=`, `--folder=`, προαιρετικό `--allow-empty`.
PublishCliParseResult parsePublishCliArgs(List<String> arguments) {
  VersionBumpKind? bumpKind;
  String? folder;
  var allowEmpty = false;

  for (final raw in arguments) {
    final arg = raw.trim();
    if (arg.isEmpty) continue;
    if (arg == '--allow-empty') {
      allowEmpty = true;
      continue;
    }
    if (arg.startsWith('--bump=')) {
      final value = arg.substring('--bump='.length).trim().toLowerCase();
      if (value == 'patch') {
        bumpKind = VersionBumpKind.patch;
      } else if (value == 'minor') {
        bumpKind = VersionBumpKind.minor;
      } else {
        return const PublishCliParseResult.error(
          'Μη έγκυρο --bump. Επιτρεπόμενες τιμές: patch, minor.',
        );
      }
      continue;
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

  if (bumpKind == null) {
    return const PublishCliParseResult.error(
      'Απαιτείται --bump=patch ή --bump=minor.',
    );
  }
  if (folder == null || folder.isEmpty) {
    return const PublishCliParseResult.error(
      'Απαιτείται --folder=<διαδρομή>.',
    );
  }

  return PublishCliParseResult.ok(
    PublishCliArgs(
      bumpKind: bumpKind,
      folder: folder,
      allowEmpty: allowEmpty,
    ),
  );
}

/// Συμπληρώνει τα placeholders `{bump}` και `{folder}` στο πρότυπο εντολής.
String buildPublishCliCommand(
  String template,
  VersionBumpKind bumpKind,
  String folder,
) {
  final bump = switch (bumpKind) {
    VersionBumpKind.patch => 'patch',
    VersionBumpKind.minor => 'minor',
  };
  return template
      .replaceAll('{bump}', bump)
      .replaceAll('{folder}', folder);
}

typedef PublishCliServiceFactory = ReleasePublisherService Function({
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
  final prompt = promptEmptyUnreleased ??
      (() => _defaultPromptEmptyUnreleased(writeLine: log));

  final factory = serviceFactory ?? _defaultServiceFactory;
  final service = factory(
    updateFolderPath: args.folder,
    onProgress: log,
  );

  late final ReleasePublishPreview preview;
  try {
    preview = await service.preparePreview();
  } catch (e) {
    log('Αποτυχία προεπισκόπησης: $e');
    return 1;
  }

  if (!preview.hasUnreleasedEntries) {
    if (args.allowEmpty) {
      log(
        'Η ενότητα Unreleased στο changelog είναι κενή. '
        'Η δημοσίευση χωρίς καταχωρήσεις δεν επιτρέπεται πλέον '
        '(το --allow-empty αγνοείται για αύξηση έκδοσης).',
      );
      return 2;
    }
    if (!interactive) {
      log(
        'Η ενότητα Unreleased στο changelog είναι κενή. '
        'Τρέξτε από διαδραστικό τερματικό ή προσθέστε καταχωρήσεις.',
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
      case EmptyUnreleasedChoice.publishAnyway:
        log(
          'Η δημοσίευση χωρίς καταχωρήσεις Unreleased δεν επιτρέπεται.',
        );
        return 2;
    }
  }

  if (args.bumpKind != preview.bumpKind) {
    log(
      'Σημείωση: το --bump=${args.bumpKind.name} αγνοείται· '
      'από το Unreleased προκύπτει αυτόματα ${preview.bumpKind.name} '
      '→ ${preview.nextVersion}.',
    );
  }

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
                'Προσθέστε καταχωρήσεις ή ξανατρέξτε με --allow-empty.',
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
  writeLine('Επιλογή [1-2]:');
  final raw = stdin.readLineSync()?.trim() ?? '';
  switch (raw) {
    case '2':
      return EmptyUnreleasedChoice.installerOnly;
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
