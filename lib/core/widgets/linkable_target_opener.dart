import 'dart:io';

import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../features/database/services/database_maintenance_service.dart';
import '../utils/linkable_text_parser.dart';

/// Αποτέλεσμα προσπάθειας ανοίγματος συνδέσμου ή διαδρομής.
enum LinkOpenResult {
  opened,
  pathNotFound,
  invalidUrl,
  urlOpenFailed,
  error,
}

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
  })  : _fileExists = fileExists ?? ((path) => File(path).exists()),
        _directoryExists = directoryExists ?? ((path) => Directory(path).exists()),
        _revealFileInExplorer = revealFileInExplorer ??
            DatabaseMaintenanceService.revealFileInExplorer,
        _openFolderInExplorer = openFolderInExplorer ??
            DatabaseMaintenanceService.openFolderInExplorer,
        _launchUrl = launchUrl ??
            ((uri) => url_launcher.launchUrl(
                  uri,
                  mode: url_launcher.LaunchMode.externalApplication,
                ));

  final FileExistsFn _fileExists;
  final DirectoryExistsFn _directoryExists;
  final RevealFileInExplorerFn _revealFileInExplorer;
  final OpenFolderInExplorerFn _openFolderInExplorer;
  final LaunchUrlFn _launchUrl;

  Future<LinkOpenResult> open({
    required String target,
    required LinkableTextKind kind,
  }) async {
    try {
      switch (kind) {
        case LinkableTextKind.url:
          return _openUrl(target);
        case LinkableTextKind.uncPath:
        case LinkableTextKind.localPath:
          return _openFilesystemPath(target);
      }
    } catch (_) {
      return LinkOpenResult.error;
    }
  }

  Future<LinkOpenResult> _openUrl(String target) async {
    final uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme) {
      return LinkOpenResult.invalidUrl;
    }
    final opened = await _launchUrl(uri);
    return opened ? LinkOpenResult.opened : LinkOpenResult.urlOpenFailed;
  }

  Future<LinkOpenResult> _openFilesystemPath(String path) async {
    final normalized = path.replaceAll('/', r'\');
    if (await _fileExists(normalized)) {
      await _revealFileInExplorer(normalized);
      return LinkOpenResult.opened;
    }
    if (await _directoryExists(normalized)) {
      await _openFolderInExplorer(normalized);
      return LinkOpenResult.opened;
    }
    return LinkOpenResult.pathNotFound;
  }
}
