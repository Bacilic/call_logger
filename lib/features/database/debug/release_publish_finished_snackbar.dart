import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/main_nav_request_provider.dart';
import '../../../core/widgets/main_nav_destination.dart';
import 'release_publish_run_provider.dart';

/// Ακούει το φινάλε της εκτέλεσης δημοσίευσης και, όταν η οθόνη Σεναρίων
/// σφαλμάτων ΔΕΝ είναι ορατή, το αναγγέλλει με snackbar με δύο επιλογές:
/// «Μετάβαση» (πίσω στην οθόνη δημοσίευσης) και «Κλείσιμο».
///
/// Καλείται μέσα από build ενός widget με ζωή εφαρμογής (το κέλυφος), όπως
/// κάθε `ref.listen`. Όταν η οθόνη είναι ορατή δεν χρειάζεται αγγελία — η
/// κάρτα δείχνει ήδη το αποτέλεσμα.
void listenForReleasePublishFinishedSnackBar(
  WidgetRef ref,
  BuildContext context, {
  required bool Function() isPublisherScreenVisible,
}) {
  ref.listen<ReleasePublishRunState>(releasePublishRunProvider, (
    previous,
    next,
  ) {
    final completion = next.completion;
    if (completion == null) return;
    if (identical(previous?.completion, completion)) return;
    if (isPublisherScreenVisible()) return;
    _showFinishedSnackBar(ref, context, completion);
  });
}

void _showFinishedSnackBar(
  WidgetRef ref,
  BuildContext context,
  ReleasePublishCompletion completion,
) {
  // Ο messenger και ο notifier πλοήγησης κρατιούνται ΤΩΡΑ: τα κουμπιά
  // πατιούνται δευτερόλεπτα αργότερα, από όποια οθόνη κι αν προβάλλεται τότε.
  final messenger = ScaffoldMessenger.of(context);
  final navRequests = ref.read(mainNavRequestProvider.notifier);
  final scheme = Theme.of(context).colorScheme;
  final isFailure = completion.isFailure;
  final foreground = isFailure ? scheme.onError : scheme.onInverseSurface;
  final actionColor = isFailure ? scheme.onError : scheme.inversePrimary;

  messenger.showSnackBar(
    SnackBar(
      key: const Key('release_publish_finished_snackbar'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 30),
      backgroundColor: isFailure ? scheme.error : null,
      content: Row(
        children: [
          Expanded(
            child: Text(
              completion.statusMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('release_publish_snackbar_go'),
            style: TextButton.styleFrom(foregroundColor: actionColor),
            onPressed: () {
              messenger.hideCurrentSnackBar();
              navRequests.request(
                const MainNavRequest(
                  destination: MainNavDestination.debugScenarios,
                ),
              );
            },
            child: const Text('Μετάβαση'),
          ),
          TextButton(
            key: const Key('release_publish_snackbar_close'),
            style: TextButton.styleFrom(foregroundColor: actionColor),
            onPressed: messenger.hideCurrentSnackBar,
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    ),
  );
}
