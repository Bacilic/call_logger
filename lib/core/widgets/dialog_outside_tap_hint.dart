import 'package:flutter/material.dart';

/// Modal διάλογος που δεν κλείνει με κλικ στο φόντο· αντί αυτού αναβοσβήνει πλαίσιο
/// (primary) γύρω από το περιεχόμενο, ως υπενθύμιση κλεισίματος με Χ ή ολοκλήρωσης.
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
      return DialogOutsideTapHintScope(
        child: Builder(builder: builder),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class DialogOutsideTapHintScope extends StatefulWidget {
  const DialogOutsideTapHintScope({required this.child, super.key});

  final Widget child;

  @override
  State<DialogOutsideTapHintScope> createState() =>
      _DialogOutsideTapHintScopeState();
}

class _DialogOutsideTapHintScopeState extends State<DialogOutsideTapHintScope> {
  bool _flashHighlight = false;
  bool _flashPlaying = false;

  Future<void> _playDoubleFlash() async {
    if (_flashPlaying || !mounted) return;
    _flashPlaying = true;
    try {
      for (var i = 0; i < 2; i++) {
        if (!mounted) return;
        setState(() => _flashHighlight = true);
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        setState(() => _flashHighlight = false);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    } finally {
      _flashPlaying = false;
    }
  }

  BorderRadiusGeometry _dialogBorderRadius(BuildContext context) {
    final shape = Theme.of(context).dialogTheme.shape;
    if (shape is RoundedRectangleBorder) {
      return shape.borderRadius;
    }
    return BorderRadius.circular(28);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = _dialogBorderRadius(context);
    final scrim = scheme.scrim.withValues(alpha: 0.54);

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _playDoubleFlash,
            behavior: HitTestBehavior.opaque,
            child: ColoredBox(color: scrim),
          ),
          Center(
            child: TapRegion(
              onTapOutside: (_) => _playDoubleFlash(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeInOut,
                decoration: _flashHighlight
                    ? BoxDecoration(
                        borderRadius: borderRadius,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: Offset.zero,
                          ),
                        ],
                      )
                    : null,
                foregroundDecoration: _flashHighlight
                    ? BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(color: scheme.primary, width: 3),
                      )
                    : null,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
