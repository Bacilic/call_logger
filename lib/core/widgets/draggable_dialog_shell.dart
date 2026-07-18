import 'package:flutter/material.dart';

/// Κινητό κέλυφος διαλόγου για desktop: σύρσιμο μόνο από τον τίτλο.
///
/// Ο διάλογος ανοίγει κεντραρισμένος (μηδενική αρχική μετατόπιση) και
/// μετακινείται με [Transform.translate]. Το σύρσιμο ενεργοποιείται μόνο
/// από την περιοχή του τίτλου — όχι από το σώμα — ώστε να μην συγκρούεται
/// με επιλογή κειμένου στα πεδία.
///
/// **Μην** τυλίγετε το περιεχόμενο σε [Scaffold] μέσα στον διάλογο·
/// επηρεάζει το κλείσιμο από κλικ στο φόντο (barrier).
class DraggableDialogShell extends StatefulWidget {
  const DraggableDialogShell({
    super.key,
    required this.title,
    required this.builder,
  });

  /// Τίτλος / λαβή συρσίματος (περνιέται στο [builder] ως titleHandle).
  final Widget title;

  /// Κατασκευάζει τον διάλογο (συνήθως [AlertDialog]) με την λαβή τίτλου.
  final Widget Function(Widget titleHandle) builder;

  @override
  State<DraggableDialogShell> createState() => _DraggableDialogShellState();
}

class _DraggableDialogShellState extends State<DraggableDialogShell> {
  Offset _offset = Offset.zero;
  final GlobalKey _dialogKey = GlobalKey();
  final GlobalKey _titleKey = GlobalKey();

  /// Όρια μετατόπισης ως προς τη θέση με μηδενικό offset (υπολογίζονται μετά το layout).
  double _minDx = double.negativeInfinity;
  double _maxDx = double.infinity;
  double _minDy = double.negativeInfinity;
  double _maxDy = double.infinity;
  bool _limitsReady = false;
  Size? _lastMediaSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLimits());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_lastMediaSize != size) {
      _lastMediaSize = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLimits());
    }
  }

  void _recomputeLimits() {
    if (!mounted) return;
    final media = MediaQuery.sizeOf(context);
    final titleBox = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    if (titleBox == null || !titleBox.hasSize) return;

    // Καθολική θέση τίτλου αν το offset ήταν μηδέν.
    final titleNow = titleBox.localToGlobal(Offset.zero);
    final titleAtZero = titleNow - _offset;
    final titleSize = titleBox.size;

    final minDx = -titleAtZero.dx;
    final maxDx = media.width - titleSize.width - titleAtZero.dx;
    final minDy = -titleAtZero.dy;
    final maxDy = media.height - titleSize.height - titleAtZero.dy;

    setState(() {
      _minDx = minDx <= maxDx ? minDx : maxDx;
      _maxDx = minDx <= maxDx ? maxDx : minDx;
      _minDy = minDy <= maxDy ? minDy : maxDy;
      _maxDy = minDy <= maxDy ? maxDy : minDy;
      _limitsReady = true;
      _offset = Offset(
        _offset.dx.clamp(_minDx, _maxDx),
        _offset.dy.clamp(_minDy, _maxDy),
      );
    });
  }

  Offset _clampOffset(Offset value) {
    if (!_limitsReady) return value;
    return Offset(
      value.dx.clamp(_minDx, _maxDx),
      value.dy.clamp(_minDy, _maxDy),
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_limitsReady) {
      _recomputeLimits();
    }
    setState(() {
      _offset = _clampOffset(_offset + details.delta);
    });
  }

  Widget _buildTitleHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onPanUpdate,
        child: KeyedSubtree(
          key: _titleKey,
          child: widget.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: _offset,
      child: KeyedSubtree(
        key: _dialogKey,
        child: widget.builder(_buildTitleHandle()),
      ),
    );
  }
}
