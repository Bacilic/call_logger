import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Κείμενο με ellipsis· tooltip μόνο όταν το κείμενο κόβεται οπτικά.
class EllipsisTooltipText extends StatefulWidget {
  const EllipsisTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.tooltipMessage,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  /// Διαφορετικό κείμενο tooltip, ορατό ΠΑΝΤΑ — και όταν δεν κόβεται τίποτα.
  ///
  /// Χρησιμεύει όταν το κελί δείχνει μια εκδοχή του κειμένου και το tooltip
  /// οφείλει να δείξει την άλλη (π.χ. καθαρό στο κελί, ωμό στο tooltip).
  final String? tooltipMessage;

  @override
  State<EllipsisTooltipText> createState() => EllipsisTooltipTextState();
}

class EllipsisTooltipTextState extends State<EllipsisTooltipText> {
  final GlobalKey _textKey = GlobalKey();
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_checkOverflow);
  }

  @override
  void didUpdateWidget(covariant EllipsisTooltipText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.maxLines != widget.maxLines) {
      WidgetsBinding.instance.addPostFrameCallback(_checkOverflow);
    }
  }

  void _checkOverflow(_) {
    if (!mounted) return;
    final ro = _textKey.currentContext?.findRenderObject();
    if (ro is! RenderParagraph) return;
    final overflows = ro.didExceedMaxLines;
    if (overflows != _overflows) {
      setState(() => _overflows = overflows);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback(_checkOverflow);
        final text = Text(
          widget.text,
          key: _textKey,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
          textAlign: widget.textAlign,
        );
        final override = widget.tooltipMessage?.trim() ?? '';
        if (override.isNotEmpty) {
          return Tooltip(message: override, child: text);
        }
        if (!_overflows || widget.text.isEmpty) return text;
        return Tooltip(message: widget.text, child: text);
      },
    );
  }
}
