import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';



import '../providers/quick_call_providers.dart';

import '../../features/calls/screens/widgets/quick_call_dialog.dart';



/// Διαδρομή asset και tooltip γρήγορης καταγραφής.

abstract final class QuickCallTrigger {

  static const String assetPath = 'assets/quick_call.png';

  static const String tooltipMessage = 'Γρήγορη Κλήση (Ctrl+Shift+N)';

  static const Key triggerKey = ValueKey('quick_call_trigger');

}



enum QuickCallFabScope {

  /// Λεξικό/Ιστορικό immersive — κανόνες κελύφους.

  shell,



  /// Routes πάνω από το κέλυφος (Ρυθμίσεις, Στατιστικά, προβολή χάρτη).

  overlayRoute,

}



/// Υπτάμενο κουμπί γρήγορης καταγραφής (FAB με εικονίδιο PNG).

class QuickCallFloatingButton extends ConsumerWidget {

  const QuickCallFloatingButton({

    super.key,

    this.scope = QuickCallFabScope.shell,

  });



  final QuickCallFabScope scope;



  @override

  Widget build(BuildContext context, WidgetRef ref) {

    final available = switch (scope) {

      QuickCallFabScope.shell => isQuickCallCaptureAvailable(ref),

      QuickCallFabScope.overlayRoute => isQuickCallOverlayFabAvailable(ref),

    };

    if (!available) {

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

    return Image.asset(

      QuickCallTrigger.assetPath,

      width: size,

      height: size,

      fit: BoxFit.contain,

      filterQuality: FilterQuality.medium,

    );

  }

}


