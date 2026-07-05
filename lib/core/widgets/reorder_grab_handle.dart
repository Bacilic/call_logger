import 'package:custom_mouse_cursor/custom_mouse_cursor.dart';
import 'package:flutter/material.dart';

/// Φόρτωση native «χεριού» μία φορά και κοινή χρήση από όλες τις λαβές.
///
/// Στα Windows 11 το [SystemMouseCursors.grab] ΔΕΝ εμφανίζεται ως χέρι (το
/// λειτουργικό δεν έχει δικό του grab cursor). Το [custom_mouse_cursor] φτιάχνει
/// πραγματικό native cursor από εικονίδιο — το ίδιο μοτίβο με τον χάρτη κτιρίου.
class _ReorderHandCursor {
  _ReorderHandCursor._();

  static Future<MouseCursor>? _future;

  static Future<MouseCursor> load() => _future ??= _create();

  static Future<MouseCursor> _create() async {
    try {
      return await CustomMouseCursor.icon(
        Icons.pan_tool_alt_outlined,
        size: 28,
        hotX: 11,
        hotY: 9,
        color: const Color(0xFF212121),
      );
    } catch (_) {
      // Χωρίς διαθέσιμο native plugin (π.χ. μέσα σε flutter test) — fallback.
      return SystemMouseCursors.grab;
    }
  }
}

/// Λαβή σύρσισης για [ReorderableListView] με πραγματικό «χέρι» στο desktop.
///
/// ΣΗΜΕΙΩΣΗ: το σχήμα του δείκτη στα Windows είναι native και επαληθεύεται ΜΟΝΟ
/// οπτικά (με το ποντίκι πάνω στη λαβή)· κανένα widget test δεν το «βλέπει».
class ReorderGrabHandle extends StatefulWidget {
  const ReorderGrabHandle({
    super.key,
    required this.index,
    this.icon = Icons.drag_handle,
    this.color,
    this.size,
    this.tooltip,
  });

  final int index;
  final IconData icon;
  final Color? color;
  final double? size;
  final String? tooltip;

  @override
  State<ReorderGrabHandle> createState() => _ReorderGrabHandleState();
}

class _ReorderGrabHandleState extends State<ReorderGrabHandle> {
  /// Fallback μέχρι να φορτωθεί ο native cursor.
  MouseCursor _cursor = SystemMouseCursors.grab;

  @override
  void initState() {
    super.initState();
    _loadCursor();
  }

  Future<void> _loadCursor() async {
    final c = await _ReorderHandCursor.load();
    if (!mounted) return;
    setState(() => _cursor = c);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      CustomMouseCursor.ensurePointersMatchDevicePixelRatio(context);
    } catch (_) {
      // no-op χωρίς διαθέσιμο native plugin.
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = Icon(widget.icon, color: widget.color, size: widget.size);
    if (widget.tooltip != null) {
      iconWidget = Tooltip(message: widget.tooltip!, child: iconWidget);
    }
    return MouseRegion(
      cursor: _cursor,
      child: ReorderableDragStartListener(
        index: widget.index,
        child: iconWidget,
      ),
    );
  }
}
