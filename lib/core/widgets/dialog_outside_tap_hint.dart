import 'package:flutter/material.dart';

/// Modal διάλογος που δεν κλείνει με κλικ στο φόντο.
///
/// Το σκοτεινό πέπλο γύρω από τον διάλογο παράγεται ΕΔΩ (το
/// [showGeneralDialog] καλείται με διαφανές barrier) — μην αφαιρεθεί το
/// [DialogOutsideTapHintScope], αλλιώς ο διάλογος μένει χωρίς υπόστρωμα.
Future<T?> showDialogWithOutsideTapHint<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
}) {
  final localizations = MaterialLocalizations.of(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    barrierDismissible: false,
    barrierLabel: localizations.scrimLabel,
    // Δικό μας scrim στο pageBuilder — αλλιώς τα κλικ στο φόντο πιάνονται από το ModalBarrier.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return DialogOutsideTapHintScope(child: Builder(builder: builder));
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

/// Υπόστρωμα διαλόγου: σκοτεινό πέπλο + κεντραρισμένο περιεχόμενο.
///
/// Η «αναβόσβηση» του υποστρώματος σε κλικ έξω εγκαταλείφθηκε (απόφαση
/// 26/07/2026): το Scaffold του DialogSnackbarScope απλώνεται σε όλη την
/// οθόνη και καταπίνει τα χτυπήματα, οπότε το flash δεν φαινόταν ποτέ.
class DialogOutsideTapHintScope extends StatelessWidget {
  const DialogOutsideTapHintScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final restScrim = scheme.scrim.withValues(alpha: 0.54);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: restScrim),
          Center(child: child),
        ],
      ),
    );
  }
}
