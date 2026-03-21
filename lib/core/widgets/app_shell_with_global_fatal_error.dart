import 'package:flutter/material.dart';

import '../database/database_init_result.dart';
import 'database_error_screen.dart';
import 'global_fatal_error_notifier.dart';

/// Εμφανίζει πλήρη οθόνη σφάλματος όταν το [globalFatalErrorNotifier] έχει τιμή, αλλιώς το [child].
class AppShellWithGlobalFatalError extends StatelessWidget {
  const AppShellWithGlobalFatalError({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DatabaseInitResult?>(
      valueListenable: globalFatalErrorNotifier,
      builder: (context, fatal, _) {
        if (fatal != null) {
          return DatabaseErrorScreen(
            result: fatal,
            dbPath: fatal.path,
            onRetry: () async {
              globalFatalErrorNotifier.value = null;
            },
          );
        }
        return child;
      },
    );
  }
}
