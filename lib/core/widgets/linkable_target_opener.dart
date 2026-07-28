import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../features/database/services/database_maintenance_service.dart';
import '../utils/linkable_text_parser.dart';

/// Αποτέλεσμα προσπάθειας ανοίγματος συνδέσμου ή διαδρομής.
enum LinkOpenResult {
  opened,
  pathNotFound,
  pathUnreachable,
  invalidUrl,
  urlOpenFailed,
  error,
}

/// Αποτέλεσμα ανοίγματος μαζί με το μήνυμα σφάλματος των Windows, όταν υπάρχει.
typedef LinkOpenOutcome = ({LinkOpenResult result, String? osMessage});

enum _PathProbeOutcome { file, directory, missing }

typedef FileExistsFn = Future<bool> Function(String path);
typedef DirectoryExistsFn = Future<bool> Function(String path);
typedef RevealFileInExplorerFn = Future<void> Function(String path);
typedef OpenFolderInExplorerFn = Future<void> Function(String path);
typedef LaunchUrlFn = Future<bool> Function(Uri uri);

/// Κοινός βοηθός ανοίγματος URL, UNC και τοπικών διαδρομών Windows.
class LinkableTargetOpener {
  LinkableTargetOpener({
    FileExistsFn? fileExists,
    DirectoryExistsFn? directoryExists,
    RevealFileInExplorerFn? revealFileInExplorer,
    OpenFolderInExplorerFn? openFolderInExplorer,
    LaunchUrlFn? launchUrl,
    this.filesystemProbeTimeout = const Duration(seconds: 5),
  }) : _fileExists = fileExists ?? ((path) => File(path).exists()),
       _directoryExists =
           directoryExists ?? ((path) => Directory(path).exists()),
       _revealFileInExplorer =
           revealFileInExplorer ??
           DatabaseMaintenanceService.revealFileInExplorer,
       _openFolderInExplorer =
           openFolderInExplorer ??
           DatabaseMaintenanceService.openFolderInExplorer,
       _launchUrl =
           launchUrl ??
           ((uri) => url_launcher.launchUrl(
             uri,
             mode: url_launcher.LaunchMode.externalApplication,
           ));

  final FileExistsFn _fileExists;
  final DirectoryExistsFn _directoryExists;
  final RevealFileInExplorerFn _revealFileInExplorer;
  final OpenFolderInExplorerFn _openFolderInExplorer;
  final LaunchUrlFn _launchUrl;

  /// Μέγιστη αναμονή για τους ελέγχους ύπαρξης αρχείου/φακέλου. Οι δικτυακές
  /// (UNC) διαδρομές προς διακομιστή που δεν αποκρίνεται μπορούν να αργήσουν
  /// δεκάδες δευτερόλεπτα λόγω SMB timeout — μετά το όριο απαντάμε
  /// [LinkOpenResult.pathUnreachable] αντί να αφήσουμε τον χρήστη χωρίς ένδειξη.
  final Duration filesystemProbeTimeout;

  /// Μήνυμα προς τον χρήστη για κάθε αποτέλεσμα· null όταν το άνοιγμα πέτυχε.
  /// Όταν τα Windows έδωσαν δικό τους μήνυμα (π.χ. «Η διαδρομή του δικτύου δεν
  /// εντοπίστηκε»), αυτό προτιμάται ως εξήγηση.
  static String? messageFor(LinkOpenOutcome outcome, String target) {
    final osMessage = outcome.osMessage;
    return switch (outcome.result) {
      LinkOpenResult.opened => null,
      LinkOpenResult.pathNotFound => 'Η διαδρομή δεν βρέθηκε: $target',
      LinkOpenResult.pathUnreachable =>
        osMessage != null && osMessage.isNotEmpty
            ? 'Δεν ήταν δυνατή η πρόσβαση: $target — $osMessage'
            : 'Η διαδρομή δεν αποκρίνεται: $target — ο διακομιστής μπορεί να '
                  'είναι απενεργοποιημένος ή εκτός δικτύου.',
      LinkOpenResult.invalidUrl => 'Μη έγκυρο URL: $target',
      LinkOpenResult.urlOpenFailed => 'Αποτυχία ανοίγματος URL.',
      LinkOpenResult.error => 'Αποτυχία ανοίγματος: $target',
    };
  }

  Future<LinkOpenOutcome> open({
    required String target,
    required LinkableTextKind kind,
  }) async {
    // return await (όχι σκέτο return): αλλιώς οι εξαιρέσεις των κλήσεων
    // ξεφεύγουν από το catch και καταλήγουν στην οθόνη σφάλματος εφαρμογής.
    try {
      switch (kind) {
        case LinkableTextKind.url:
          return await _openUrl(target);
        case LinkableTextKind.uncPath:
        case LinkableTextKind.localPath:
          return await _openFilesystemPath(target);
      }
    } catch (_) {
      return (result: LinkOpenResult.error, osMessage: null);
    }
  }

  Future<LinkOpenOutcome> _openUrl(String target) async {
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) {
      return (result: LinkOpenResult.invalidUrl, osMessage: null);
    }
    final opened = await _launchUrl(uri);
    return (
      result: opened ? LinkOpenResult.opened : LinkOpenResult.urlOpenFailed,
      osMessage: null,
    );
  }

  Future<LinkOpenOutcome> _openFilesystemPath(String path) async {
    final normalized = path.replaceAll('/', r'\');
    final _PathProbeOutcome probe;
    try {
      probe = await _probePath(normalized).timeout(filesystemProbeTimeout);
    } on TimeoutException {
      return (result: LinkOpenResult.pathUnreachable, osMessage: null);
    } on FileSystemException catch (e) {
      // Στα Windows, έλεγχος ύπαρξης σε μη προσβάσιμη UNC διαδρομή πετάει
      // εξαίρεση (π.χ. errno 53) αντί να επιστρέψει false.
      return (
        result: LinkOpenResult.pathUnreachable,
        osMessage: e.osError?.message.trim(),
      );
    }
    switch (probe) {
      case _PathProbeOutcome.file:
        await _revealFileInExplorer(normalized);
        return (result: LinkOpenResult.opened, osMessage: null);
      case _PathProbeOutcome.directory:
        await _openFolderInExplorer(normalized);
        return (result: LinkOpenResult.opened, osMessage: null);
      case _PathProbeOutcome.missing:
        return (result: LinkOpenResult.pathNotFound, osMessage: null);
    }
  }

  Future<_PathProbeOutcome> _probePath(String path) async {
    if (await _fileExists(path)) return _PathProbeOutcome.file;
    if (await _directoryExists(path)) return _PathProbeOutcome.directory;
    return _PathProbeOutcome.missing;
  }
}
