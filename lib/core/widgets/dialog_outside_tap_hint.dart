import 'package:flutter/material.dart';

/// Εξωτερική λαβή για αναβόσβηση πλαισίου χωρίς νέο άνοιγμα διαλόγου.
class DialogOutsideTapHintController {
  _DialogOutsideTapHintScopeState? _state;

  bool get isAttached => _state != null;

  void flash() => _state?._playDoubleFlash();
}

/// Modal διάλογος που δεν κλείνει με κλικ στο φόντο· αντί αυτού αναβοσβήνει πλαίσιο
/// (primary) γύρω από το περιεχόμενο, ως υπενθύμιση κλεισίματος με Χ ή ολοκλήρωσης.
Future<T?> showDialogWithOutsideTapHint<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  DialogOutsideTapHintController? controller,
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
        controller: controller,
        child: Builder(builder: builder),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class DialogOutsideTapHintScope extends StatefulWidget {
  const DialogOutsideTapHintScope({
    required this.child,
    this.controller,
    super.key,
  });

  final Widget child;
  final DialogOutsideTapHintController? controller;

  @override
  State<DialogOutsideTapHintScope> createState() =>
      _DialogOutsideTapHintScopeState();
}

class _DialogOutsideTapHintScopeState extends State<DialogOutsideTapHintScope> {
  bool _flashHighlight = false;
  bool _flashPlaying = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    if (identical(widget.controller?._state, this)) {
      widget.controller?._state = null;
    }
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Υπόστρωμα σε ηρεμία: σκοτεινό πέπλο. Κατά το flash: στιγμιαία primary απόχρωση,
    // ώστε να είναι ορατό χωρίς να σκεπάζει τον διάλογο (που επιπλέει από πάνω).
    final restScrim = scheme.scrim.withValues(alpha: 0.54);
    final flashScrim = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.35),
      restScrim,
    );

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: _playDoubleFlash,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              key: const ValueKey('dialog_flash_backdrop'),
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: _flashHighlight ? flashScrim : restScrim,
              ),
              foregroundDecoration: _flashHighlight
                  ? BoxDecoration(
                      border: Border.all(color: scheme.primary, width: 4),
                    )
                  : null,
            ),
          ),
          Center(child: widget.child),
        ],
      ),
    );
  }
}
