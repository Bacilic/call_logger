import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';

import '../../../../../core/models/floor_plan_object.dart';
import '../../../../../core/models/floor_plan_object_kind.dart';
import '../floor_plan_cabinet.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../../../../../core/widgets/compact_tooltip.dart';
import '../services/floor_plan_cabinet_preferences.dart';
import 'floor_plan_port_facade.dart';
import 'floor_plan_symbol_painter.dart';

/// Το ύψος μιας θέσης U στην όψη της καμπίνας, σε pixel.
const double _kSlot = 24;

/// Οι ενέργειες της σχεδίασης πάνω στο περιεχόμενο της καμπίνας. Χωρίς
/// αυτές (προβολή) το πάνελ μόνο δείχνει.
class FloorPlanCabinetActions {
  const FloorPlanCabinetActions({
    required this.addableKinds,
    required this.onAdd,
    required this.onMove,
    required this.onEdit,
    required this.onSetHeight,
    required this.onTakeOut,
    required this.onDelete,
    required this.onSetUnits,
    this.onEditWrittenName,
  });

  /// Τα είδη που μπαίνουν σε καμπίνα, αλφαβητικά.
  final List<FloorPlanObjectKind> addableKinds;
  final void Function(int kindId) onAdd;
  final void Function(int objectId, int u) onMove;
  final void Function(int objectId) onEdit;
  final void Function(int objectId, int height) onSetHeight;
  final void Function(int objectId) onTakeOut;
  final void Function(int objectId) onDelete;
  final void Function(int units) onSetUnits;

  /// Κλικ σε θύρα της πρόσοψης: «Γραμμένο όνομα…».
  final void Function(FloorPlanObject object, FloorPlanPort port)?
  onEditWrittenName;
}

/// Το πάνελ της καμπίνας: η **πιστή όψη** της, από το U1 (πάνω) ως το
/// τελευταίο U, με κάθε αντικείμενο στη θέση του και τα κενά U ανάμεσα.
///
/// Δύο ζώνες (απόφαση 30/10/2026): πάνω η όψη, που κυλά όταν δεν χωρά·
/// κάτω οι **προσόψεις των επιλεγμένων συσκευών**, που μένουν πάντα ορατές.
/// Κλικ σε συσκευή με θύρες τη σημειώνει ή την ξε-σημειώνει· η επιλογή
/// κάθε καμπίνας θυμάται ανά χρήστη, και από προεπιλογή είναι κενή. Η λωρίδα
/// ανάμεσα στις ζώνες σύρεται.
///
/// Στη σχεδίαση ([actions]): σύρσιμο σε άλλο U μετακινεί το αντικείμενο,
/// διπλό κλικ ανοίγει τα στοιχεία του, το μενού του αλλάζει ύψος, το βγάζει
/// από την καμπίνα ή το σβήνει, «Προσθήκη» βάζει νέο στο πρώτο ελεύθερο U.
class FloorPlanCabinetPanel extends StatefulWidget {
  const FloorPlanCabinetPanel({
    super.key,
    required this.title,
    required this.units,
    required this.contents,
    required this.kinds,
    required this.onClose,
    this.ports = const [],
    this.occupiedPortIds = const {},
    this.portAutoName,
    this.where,
    this.actions,
    this.cabinetId,
    this.initialSelection = const {},
    this.facadeHeight = FloorPlanCabinetLayout.defaultFacadeHeight,
    this.onFacadeResize,
    this.onLayoutDone,
    this.onTitleDrag,
  });

  /// Το όνομα της καμπίνας· `null` όταν δεν έχει δοθεί ακόμη.
  final String? title;

  /// Πού βρίσκεται: χώρος ή τμήμα.
  final String? where;
  final int units;
  final List<FloorPlanObject> contents;
  final Map<int, FloorPlanObjectKind> kinds;
  final VoidCallback onClose;

  /// Οι θύρες του περιεχομένου (μπορεί και άλλων αντικειμένων — φιλτράρονται
  /// εδώ) και ποιες έχουν καλώδιο.
  final List<FloorPlanPort> ports;
  final Set<int> occupiedPortIds;

  /// Το αυτόματο όνομα μιας θύρας («RC6.F17»).
  final String Function(FloorPlanObject object, FloorPlanPort port)?
  portAutoName;
  final FloorPlanCabinetActions? actions;

  /// Η καμπίνα, για να διαβαστούν και να γραφτούν οι επιλεγμένες συσκευές
  /// της. Χωρίς αυτήν ισχύει το [initialSelection] και τίποτα δεν γράφεται.
  final int? cabinetId;
  final Set<int> initialSelection;

  /// Το ύψος της ζώνης των προσόψεων, και η λαβή που το αλλάζει.
  final double facadeHeight;
  final ValueChanged<double>? onFacadeResize;

  /// Τέλος συρσίματος (θέση, μέγεθος, λωρίδα) — τότε γράφεται η ρύθμιση.
  final VoidCallback? onLayoutDone;

  /// Σύρσιμο από τη μπάρα τίτλου: μετακίνηση του πάνελ.
  final ValueChanged<Offset>? onTitleDrag;

  @override
  State<FloorPlanCabinetPanel> createState() => _FloorPlanCabinetPanelState();
}

class _FloorPlanCabinetPanelState extends State<FloorPlanCabinetPanel> {
  final GlobalKey _rackKey = GlobalKey();

  /// Πού θα έπεφτε αυτό που σύρεται: πρώτο U και ύψος.
  ({int u, int height})? _dropAt;

  /// Οι συσκευές που δείχνουν την πρόσοψή τους.
  late Set<int> _selected = {...widget.initialSelection};

  /// Το προηγούμενο κλικ, για το διπλό κλικ χωρίς καθυστέρηση στο μονό.
  ({int id, DateTime at})? _lastTap;

  @override
  void initState() {
    super.initState();
    _loadSelection();
  }

  @override
  void didUpdateWidget(FloorPlanCabinetPanel old) {
    super.didUpdateWidget(old);
    if (old.cabinetId != widget.cabinetId) {
      _selected = {...widget.initialSelection};
      _loadSelection();
    }
  }

  Future<void> _loadSelection() async {
    final id = widget.cabinetId;
    if (id == null) return;
    final stored = await FloorPlanCabinetPreferences.readSelection(id);
    if (!mounted || widget.cabinetId != id) return;
    setState(() => _selected = stored);
  }

  void _toggle(FloorPlanObject o) {
    if (!_hasPorts(o)) return;
    setState(() {
      if (!_selected.remove(o.id)) _selected.add(o.id);
    });
    final id = widget.cabinetId;
    if (id != null) {
      FloorPlanCabinetPreferences.writeSelection(id, {..._selected});
    }
  }

  /// Κλικ σε συσκευή: εναλλάσσει την επιλογή **αμέσως**. Δεύτερο κλικ μέσα
  /// στον χρόνο του διπλού την επαναφέρει και ανοίγει τα στοιχεία — ώστε το
  /// μονό κλικ να μην περιμένει μήπως έρθει δεύτερο.
  void _onBlockTap(FloorPlanObject o) {
    final now = DateTime.now();
    final last = _lastTap;
    final isDouble =
        last != null &&
        last.id == o.id &&
        now.difference(last.at) <= kDoubleTapTimeout * 2;
    _lastTap = isDouble ? null : (id: o.id, at: now);
    _toggle(o);
    if (isDouble) widget.actions?.onEdit(o.id);
  }

  List<FloorPlanPort> _portsOf(int objectId) => [
    for (final p in widget.ports)
      if (p.objectId == objectId) p,
  ]..sort((a, b) => a.number.compareTo(b.number));

  bool _hasPorts(FloorPlanObject o) =>
      widget.kinds[o.kindId]?.symbol?.hasPortCount ?? false;

  /// «24 θύρες · 3 ελεύθερες» — μόνο για όσα δηλώνουν θύρες και έχουν.
  String? _portSummary(FloorPlanObject o) {
    if (!_hasPorts(o)) return null;
    final ports = _portsOf(o.id);
    if (ports.isEmpty) return null;
    final free = ports.where((p) => !widget.occupiedPortIds.contains(p.id));
    return '${ports.length} θύρες · ${free.length} ελεύθερες';
  }

  String _label(FloorPlanObject o) {
    final name = o.name?.trim() ?? '';
    final kind = widget.kinds[o.kindId]?.name ?? 'Αντικείμενο';
    return name.isEmpty ? kind : '$kind $name';
  }

  int? _uUnder(Offset global) {
    final box = _rackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    return floorPlanRackUAt(local.dy, _kSlot, widget.units);
  }

  FloorPlanObject? _byId(int id) {
    for (final o in widget.contents) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = widget.actions;
    final rows = floorPlanRackRows(widget.units, widget.contents);
    final subtitle = [?widget.where, '${widget.units}U'].join(' · ');
    final shown = [
      for (final o in widget.contents)
        if (_hasPorts(o) && _selected.contains(o.id)) o,
    ];
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: widget.onTitleDrag == null
                ? MouseCursor.defer
                : SystemMouseCursors.move,
            child: GestureDetector(
              onPanUpdate: widget.onTitleDrag == null
                  ? null
                  : (d) => widget.onTitleDrag!(d.delta),
              onPanEnd: (_) => widget.onLayoutDone?.call(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title == null
                                ? 'Καμπίνα'
                                : 'Καμπίνα ${widget.title}',
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actions != null)
                      TextButton(
                        onPressed: () => _askUnits(context, actions),
                        child: const Text('Θέσεις U…'),
                      ),
                    IconButton(
                      tooltip: 'Κλείσιμο',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // Η όψη: κυλά μόνη της όταν δεν χωρά.
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _rack(theme, rows, actions),
              ),
            ),
          ),
          _splitter(theme),
          // Οι προσόψεις των επιλεγμένων: πάντα ορατές.
          SizedBox(
            height: widget.facadeHeight,
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Κλικ σε συσκευή της καμπίνας για να δείτε την '
                        'πρόσοψή της.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        for (final o in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FloorPlanPortFacade(
                              title: _label(o),
                              symbol: widget.kinds[o.kindId]?.symbol,
                              ports: _portsOf(o.id),
                              occupied: widget.occupiedPortIds,
                              autoName: (port) =>
                                  widget.portAutoName?.call(o, port) ??
                                  'Θύρα ${port.number}',
                              onEditWrittenName:
                                  actions?.onEditWrittenName == null
                                  ? null
                                  : (port) =>
                                        actions!.onEditWrittenName!(o, port),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (actions != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  _addButton(actions),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Σύρετε σε άλλο U · διπλό κλικ: στοιχεία',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Η λωρίδα ανάμεσα στην όψη και στις προσόψεις: σύρεται πάνω-κάτω.
  Widget _splitter(ThemeData theme) {
    final resize = widget.onFacadeResize;
    return MouseRegion(
      cursor: resize == null ? MouseCursor.defer : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: resize == null
            ? null
            : (d) => resize(widget.facadeHeight - d.delta.dy),
        onVerticalDragEnd: (_) => widget.onLayoutDone?.call(),
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rack(
    ThemeData theme,
    List<FloorPlanRackRow> rows,
    FloorPlanCabinetActions? actions,
  ) {
    final column = Column(
      key: _rackKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final row in rows) _row(theme, row, actions)],
    );
    final drop = _dropAt;
    final stacked = Stack(
      children: [
        column,
        if (drop != null)
          Positioned(
            left: 44,
            right: 0,
            top: (drop.u - 1) * _kSlot,
            height: drop.height * _kSlot,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
    if (actions == null) return stacked;
    return DragTarget<int>(
      onMove: (details) {
        final u = _uUnder(details.offset + const Offset(0, _kSlot / 2));
        final object = _byId(details.data);
        if (u == null || object == null) return;
        final next = (u: u, height: object.heightU);
        if (next != _dropAt) setState(() => _dropAt = next);
      },
      onLeave: (_) => setState(() => _dropAt = null),
      onAcceptWithDetails: (details) {
        setState(() => _dropAt = null);
        final u = _uUnder(details.offset + const Offset(0, _kSlot / 2));
        if (u != null) actions.onMove(details.data, u);
      },
      builder: (context, candidates, rejected) => stacked,
    );
  }

  Widget _row(
    ThemeData theme,
    FloorPlanRackRow row,
    FloorPlanCabinetActions? actions,
  ) {
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final uLabels = SizedBox(
      width: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('U${row.fromU}', style: labelStyle),
          if (row.heightU > 1) Text('U${row.toU}', style: labelStyle),
        ],
      ),
    );
    final object = row.object;
    final Widget body;
    if (object == null) {
      body = Container(
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.center,
        child: Text(
          row.heightU == 1 ? 'κενό' : 'κενό U${row.fromU}–U${row.toU}',
          style: labelStyle,
        ),
      );
    } else {
      final block = _block(theme, object, row.heightU, actions);
      final tappable = GestureDetector(
        onTap: () => _onBlockTap(object),
        child: MouseRegion(
          cursor: _hasPorts(object)
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          child: block,
        ),
      );
      body = actions == null
          ? tappable
          : Draggable<int>(
              data: object.id,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 300,
                  height: row.heightU * _kSlot,
                  child: Opacity(opacity: 0.85, child: block),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: block),
              onDragEnd: (_) {
                if (_dropAt != null) setState(() => _dropAt = null);
              },
              child: tappable,
            );
    }
    return SizedBox(
      height: row.heightU * _kSlot,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          uLabels,
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _block(
    ThemeData theme,
    FloorPlanObject object,
    int heightU,
    FloorPlanCabinetActions? actions,
  ) {
    final symbol = widget.kinds[object.kindId]?.symbol;
    final colors = floorPlanSymbolColors(symbol);
    final selected = _selected.contains(object.id) && _hasPorts(object);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1.5),
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: colors.fill,
        border: Border.all(
          color: selected ? theme.colorScheme.primary : colors.line,
          width: selected ? 2 : 0.8,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 2),
          ],
          FloorPlanSymbolIcon(symbol, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                heightU > 1 ? '${_label(object)} ($heightU U)' : _label(object),
                ?_portSummary(object),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions != null) _menu(object, actions),
        ],
      ),
    );
  }

  Widget _menu(FloorPlanObject object, FloorPlanCabinetActions actions) {
    return PopupMenuButton<String>(
      tooltip: 'Ενέργειες',
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: const Icon(Icons.more_vert, color: Colors.black87),
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            actions.onEdit(object.id);
          case 'height':
            final height = await _askNumber(
              context,
              title: 'Ύψος σε U',
              label: 'Πόσα U πιάνει',
              initial: object.heightU,
              max: widget.units,
            );
            if (height != null) actions.onSetHeight(object.id, height);
          case 'out':
            actions.onTakeOut(object.id);
          case 'delete':
            actions.onDelete(object.id);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Στοιχεία…')),
        PopupMenuItem(value: 'height', child: Text('Ύψος σε U…')),
        PopupMenuItem(value: 'out', child: Text('Βγάλε από την καμπίνα')),
        PopupMenuItem(value: 'delete', child: Text('Διαγραφή')),
      ],
    );
  }

  Widget _addButton(FloorPlanCabinetActions actions) {
    final kinds = actions.addableKinds;
    if (kinds.isEmpty) {
      return const CompactTooltip(
        message:
            'Ορίστε πρώτα ένα είδος (π.χ. switch) στα «Είδη αντικειμένων».',
        child: OutlinedButton(onPressed: null, child: Text('+ Προσθήκη')),
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final kind in kinds)
          MenuItemButton(
            leadingIcon: FloorPlanSymbolIcon(kind.symbol, size: 20),
            onPressed: () => actions.onAdd(kind.id),
            child: Text(kind.name),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add),
        label: const Text('Προσθήκη'),
      ),
    );
  }

  Future<void> _askUnits(
    BuildContext context,
    FloorPlanCabinetActions actions,
  ) async {
    final units = await _askNumber(
      context,
      title: 'Θέσεις καμπίνας',
      label: 'Πόσα U έχει η καμπίνα',
      initial: widget.units,
      max: kFloorPlanMaxCabinetUnits,
    );
    if (units != null) actions.onSetUnits(units);
  }
}

/// Ζητά έναν ακέραιο από 1 ως [max]· `null` όταν ακυρωθεί.
Future<int?> _askNumber(
  BuildContext context, {
  required String title,
  required String label,
  required int initial,
  required int max,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) =>
        _NumberDialog(title: title, label: label, initial: initial, max: max),
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.max,
  });

  final String title;
  final String label;
  final int initial;
  final int max;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _text = TextEditingController(text: '${widget.initial}')
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: '${widget.initial}'.length,
    );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_text.text.trim());
    if (value == null || value < 1 || value > widget.max) {
      setState(() => _error = 'Από 1 ως ${widget.max}.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Αποθήκευση')),
      ],
    );
  }
}
