import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/quick_call_providers.dart';

import '../../features/calls/provider/quick_call_session_provider.dart';
import '../../features/calls/screens/widgets/quick_call_dialog.dart';

import 'app_asset_image.dart';

/// Διαδρομή asset και tooltip γρήγορης καταγραφής.

abstract final class QuickCallTrigger {
  static const String assetPath = 'assets/quick_call.png';

  static const String tooltipMessage = 'Γρήγορη Κλήση (Ctrl+Shift+N)';

  static const Key triggerKey = ValueKey('quick_call_trigger');

  static const String minimizedTooltip = 'Επαναφορά γρήγορης καταγραφής';

  static const Key minimizedKey = ValueKey('quick_call_minimized_phone');
}

/// Υπτάμενο κουμπί γρήγορης καταγραφής (FAB με εικονίδιο PNG).
///
/// Με ελαχιστοποιημένη γρήγορη καταγραφή γίνεται τηλέφωνο που χτυπά και την
/// επαναφέρει. Το τηλέφωνο φαίνεται ακόμη κι αν ο χρήστης έχει κρύψει το
/// κουμπί από τις Ρυθμίσεις: δεν είναι κουμπί, είναι κλήση σε εξέλιξη.
class QuickCallFloatingButton extends ConsumerWidget {
  const QuickCallFloatingButton({super.key, this.showOpenButton = true});

  /// `false` όπου δεν υπάρχει κουμπί ανοίγματος (κύριες οθόνες): εκεί
  /// εμφανίζεται μόνο το τηλέφωνο της ελαχιστοποιημένης καταγραφής.
  final bool showOpenButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimized =
        ref.watch(quickCallSessionProvider) == QuickCallPhase.minimized;
    if (minimized) {
      if (isQuickCallOverlayBlocked(ref)) return const SizedBox.shrink();
      return const _RingingPhoneButton();
    }

    if (!showOpenButton || !isQuickCallCaptureAvailable(ref)) {
      return const SizedBox.shrink();
    }

    return const _QuickCallPressableFab();
  }
}

/// FAB με ελαφριά σκιά, διαφάνεια και εφέ βύθισης στο πάτημα.

class _QuickCallPressableFab extends StatefulWidget {
  const _QuickCallPressableFab();

  static const double _iconSize = 44;

  static const double _restOpacity = 0.9;

  @override
  State<_QuickCallPressableFab> createState() => _QuickCallPressableFabState();
}

class _QuickCallPressableFabState extends State<_QuickCallPressableFab> {
  bool _pressed = false;

  bool _hovered = false;

  void _openDialog() => showQuickCallDialog(context);

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.94 : (_hovered ? 1.02 : 1.0);

    final slideY = _pressed ? 3.0 : (_hovered ? -1.5 : 0.0);

    final opacity = _pressed ? 0.82 : _QuickCallPressableFab._restOpacity;

    final shadow = _pressed
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),

              blurRadius: 3,

              offset: const Offset(0, 1),
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),

              blurRadius: 7,

              offset: const Offset(0, 3),
            ),
          ];

    return Tooltip(
      message: QuickCallTrigger.tooltipMessage,

      child: Semantics(
        button: true,

        label: QuickCallTrigger.tooltipMessage,

        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),

          onExit: (_) => setState(() {
            _hovered = false;

            _pressed = false;
          }),

          child: GestureDetector(
            key: QuickCallTrigger.triggerKey,

            onTapDown: (_) => setState(() => _pressed = true),

            onTapUp: (_) => setState(() => _pressed = false),

            onTapCancel: () => setState(() => _pressed = false),

            onTap: _openDialog,

            child: AnimatedScale(
              scale: scale,

              duration: const Duration(milliseconds: 120),

              curve: Curves.easeOutCubic,

              child: AnimatedSlide(
                offset: Offset(0, slideY / _QuickCallPressableFab._iconSize),

                duration: const Duration(milliseconds: 120),

                curve: Curves.easeOutCubic,

                child: AnimatedOpacity(
                  opacity: opacity,

                  duration: const Duration(milliseconds: 100),

                  child: DecoratedBox(
                    decoration: BoxDecoration(boxShadow: shadow),

                    child: const _QuickCallIcon(
                      size: _QuickCallPressableFab._iconSize,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCallIcon extends StatelessWidget {
  const _QuickCallIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return AppAssetImage(
      assetPath: QuickCallTrigger.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      fallbackIcon: Icons.call,
    );
  }
}

/// Η ελαχιστοποιημένη γρήγορη καταγραφή: τηλέφωνο που χτυπά, ώστε ο χρήστης
/// να βλέπει πάντα ότι υπάρχει κλήση σε εξέλιξη. Ένα κλικ την επαναφέρει.
class _RingingPhoneButton extends StatefulWidget {
  const _RingingPhoneButton();

  @override
  State<_RingingPhoneButton> createState() => _RingingPhoneButtonState();
}

class _RingingPhoneButtonState extends State<_RingingPhoneButton>
    with SingleTickerProviderStateMixin {
  /// Ένας κύκλος: κουδούνισμα στο πρώτο τρίτο, ησυχία στο υπόλοιπο — όπως
  /// χτυπά ένα τηλέφωνο.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  /// Γωνία κλίσης για τη θέση [t] (0–1) του κύκλου.
  static double _tilt(double t) {
    const ringPart = 1 / 3;
    if (t >= ringPart) return 0;
    final progress = t / ringPart;
    // Έξι γρήγορες ταλαντώσεις που σβήνουν προς το τέλος του κουδουνίσματος.
    return math.sin(progress * math.pi * 12) * 0.35 * (1 - progress);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: QuickCallTrigger.minimizedTooltip,
      child: FloatingActionButton(
        key: QuickCallTrigger.minimizedKey,
        heroTag: null,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onPressed: () => showQuickCallDialog(context),
        child: AnimatedBuilder(
          animation: _ring,
          builder: (context, child) =>
              Transform.rotate(angle: _tilt(_ring.value), child: child),
          child: const Icon(Icons.ring_volume),
        ),
      ),
    );
  }
}
