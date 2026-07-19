import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Αναγνώριση builds ανάπτυξης (debug ή φάκελος `build\windows`).
class BuildEnvironment {
  BuildEnvironment._();

  /// `true` αν το build είναι ανάπτυξης και δεν πρέπει να αυτο-ενημερώνεται.
  ///
  /// Οι παράμετροι είναι injectable για τεστ· στην πράξη χρησιμοποιούνται
  /// [kDebugMode] και [AppConfig.applicationExecutableDirectory].
  static bool isDevelopmentBuild({
    String? executablePath,
    bool? isDebug,
  }) {
    if (isDebug ?? kDebugMode) {
      return true;
    }

    final raw = executablePath ??
        (() {
          try {
            final exe = Platform.resolvedExecutable;
            if (exe.isNotEmpty) return exe;
          } catch (_) {}
          return AppConfig.applicationExecutableDirectory;
        })();

    final normalized = raw.replaceAll('/', r'\').toLowerCase();
    return normalized.contains(r'\build\windows\');
  }
}
