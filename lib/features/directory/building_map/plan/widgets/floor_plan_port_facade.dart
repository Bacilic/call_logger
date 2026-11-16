import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_object_kind.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_ports.dart';

/// Η **πρόσοψη** ενός patch panel, switch, router ή POE: κάθε θύρα στη θέση
/// της, γεμάτη όταν έχει καλώδιο, άδεια όταν είναι ελεύθερη.
///
/// Πέρασμα του ποντικιού: όνομα, γραμμένο όνομα, σύνδεση. Στη σχεδίαση το κλικ
/// σε θύρα φτιάχνει ή αφαιρεί καλώδιο ([onPortTap]), το δεξί κλικ ανοίγει το
/// «Γραμμένο όνομα…» ([onEditWrittenName]).
class FloorPlanPortFacade extends StatelessWidget {
  const FloorPlanPortFacade({
    super.key,
    required this.title,
    required this.symbol,
    required this.ports,
    this.groups = const [],
    required this.occupied,
    required this.autoName,
    this.onEditWrittenName,
    this.detailOf,
    this.onPortTap,
    this.pendingPortId,
    this.backOccupied = const {},
    this.frontOccupied = const {},
  });

  /// Π.χ. «Switch SW-2».
  final String title;
  final FloorPlanSymbol? symbol;
  final List<FloorPlanPort> ports;

  /// Οι ομάδες θυρών της συσκευής: κάθε μία σχεδιάζεται ως χωριστό μπλοκ, με
  /// την ταχύτητά της από πάνω (απόφαση 14/11/2026).
  final List<FloorPlanPortGroup> groups;
  final Set<int> occupied;
  final String Function(FloorPlanPort port) autoName;
  final void Function(FloorPlanPort port)? onEditWrittenName;

  /// Με τι συνδέεται η θύρα, για την υπόδειξη.
  final String? Function(FloorPlanPort port)? detailOf;

  /// Κλικ σε θύρα (σχεδίαση), με το σημείο της οθόνης όπου έγινε.
  final void Function(FloorPlanPort port, Offset globalPosition)? onPortTap;

  /// Η θύρα απ' όπου ξεκίνησε το καλώδιο που φτιάχνεται τώρα.
  final int? pendingPortId;

  /// Οι δύο πλευρές της θύρας patch panel: το κάτω μισό γεμίζει με καλώδιο
  /// πίσω, το πάνω με καλώδιο μπροστά.
  final Set<int> backOccupied;
  final Set<int> frontOccupied;

  _PortFill _fillOf(FloorPlanPort port) {
    if (symbol != FloorPlanSymbol.patchPanel) {
      return occupied.contains(port.id) ? _PortFill.full : _PortFill.none;
    }
    final back = backOccupied.contains(port.id);
    final front = frontOccupied.contains(port.id);
    if (back && front) return _PortFill.full;
    if (back) return _PortFill.lowerHalf;
    return front ? _PortFill.upperHalf : _PortFill.none;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final free = ports.where((p) => !occupied.contains(p.id)).length;
    final caption = ports.isEmpty
        ? '$title · δεν έχουν δηλωθεί θύρες'
        : '$title · ${ports.length} θύρες · $free ελεύθερες';
    final blocks = <int, List<FloorPlanPort>>{};
    for (final p in [...ports]..sort(floorPlanComparePorts)) {
      (blocks[p.groupIndex] ??= []).add(p);
    }
    final order = blocks.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caption, style: theme.textTheme.labelMedium),
        if (ports.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: order.length == 1 && _speedOf(order.single) == null
                ? _block(blocks[order.single]!)
                // Μία ομάδα = ένα μπλοκ· κάθε μπλοκ πλατύ όσο οι στήλες του,
                // με κενό ανάμεσα, όπως τα uplink στο πλάι του switch.
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, g) in order.indexed) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Flexible(
                          flex: _columnsWanted(blocks[g]!.length),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _speedOf(g) ?? '',
                                style: theme.textTheme.labelSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              _block(blocks[g]!, fit: true),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  String? _speedOf(int group) {
    if (group >= groups.length) return null;
    final speed = groups[group].speed?.trim() ?? '';
    return speed.isEmpty ? null : speed;
  }

  /// Πόσες στήλες θα ήθελε ένα μπλοκ [count] θυρών χωρίς στένεμα.
  int _columnsWanted(int count) {
    final columns = symbol == FloorPlanSymbol.patchPanel
        ? count
        : (count + 1) ~/ 2;
    return columns.clamp(1, kFloorPlanFacadeMaxColumns);
  }

  /// Οι θύρες μιας ομάδας στις θέσεις τους. Όλες ορατές χωρίς κύλιση: ως 24
  /// ανά σειρά, και οι θύρες μεγαλώνουν ή μικραίνουν με το πλάτος· ό,τι δεν
  /// χωρά πάει σε επόμενη σειρά.
  ///
  /// Με [fit] το μπλοκ δεν απλώνει πέρα από όσες στήλες χρειάζεται, ώστε τα
  /// μπλοκ πλάι-πλάι να έχουν ίδιο μέγεθος θύρας.
  Widget _block(List<FloorPlanPort> group, {bool fit = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 2.0;
        final fitting = floorPlanFacadeColumns(constraints.maxWidth, gap: gap);
        final wanted = _columnsWanted(group.length);
        final columns = fit && wanted < fitting ? wanted : fitting;
        final box = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in floorPlanFacadeRows(
              symbol,
              group.length,
              columns: columns,
            ))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    for (final (i, position) in row.indexed) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: box,
                        height: 20,
                        child: _portBox(group[position - 1]),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _portBox(FloorPlanPort port) => _PortBox(
    port: port,
    fill: _fillOf(port),
    name: autoName(port),
    detail: detailOf?.call(port),
    pending: pendingPortId == port.id,
    hasFrontCable: symbol == FloorPlanSymbol.patchPanel
        ? frontOccupied.contains(port.id)
        : occupied.contains(port.id),
    onTap: onPortTap == null ? null : (at) => onPortTap!(port, at),
    onSecondaryTap: onEditWrittenName == null
        ? null
        : () => onEditWrittenName!(port),
  );
}

/// Πόσο γεμάτη είναι μια θύρα. Μισή μόνο η θύρα patch panel, που έχει δύο
/// πλευρές.
enum _PortFill { none, lowerHalf, upperHalf, full }

class _PortBox extends StatelessWidget {
  const _PortBox({
    required this.port,
    required this.fill,
    required this.name,
    required this.pending,
    required this.hasFrontCable,
    this.detail,
    this.onTap,
    this.onSecondaryTap,
  });

  final FloorPlanPort port;
  final _PortFill fill;
  final String name;
  final bool pending;
  final bool hasFrontCable;
  final String? detail;
  final void Function(Offset globalPosition)? onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final written = port.writtenName;
    final tooltip = [
      name,
      if (written != null) 'Γραμμένο: $written',
      fill == _PortFill.none ? 'Ελεύθερη' : 'Κατειλημμένη',
      ?detail,
      if (onTap != null)
        hasFrontCable ? 'Κλικ: αφαίρεση καλωδίου' : 'Κλικ: νέο καλώδιο',
      if (onSecondaryTap != null) 'Δεξί κλικ: «Γραμμένο όνομα…»',
    ].join('\n');
    final full = fill == _PortFill.full;
    final box = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Γεμάτη = κατειλημμένη, άδεια = ελεύθερη — μόνο αυτό σημαίνει το
        // γέμισμα.
        color: full ? ink.withValues(alpha: 0.85) : null,
        border: Border.all(
          color: pending ? theme.colorScheme.primary : ink,
          width: pending ? 2.5 : 1,
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Η μισή θύρα είναι πιο ανοιχτή, ώστε ο αριθμός να διαβάζεται και
          // όταν το γέμισμα τον κόβει στη μέση.
          if (fill == _PortFill.lowerHalf || fill == _PortFill.upperHalf)
            FractionallySizedBox(
              alignment: fill == _PortFill.lowerHalf
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              heightFactor: 0.5,
              widthFactor: 1,
              child: ColoredBox(color: ink.withValues(alpha: 0.35)),
            ),
          Center(
            child: Text(
              '${port.number}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                color: full ? theme.colorScheme.surface : ink,
              ),
            ),
          ),
          // Γραμμένο όνομα: μικρή γωνία, ώστε να μη μοιάζει με κατειλημμένη.
          if (written != null)
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                size: const Size(6, 6),
                painter: _CornerPainter(theme.colorScheme.tertiary),
              ),
            ),
        ],
      ),
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: onTap == null && onSecondaryTap == null
          ? box
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTapUp: onTap == null
                    ? null
                    : (details) => onTap!(details.globalPosition),
                onSecondaryTap: onSecondaryTap,
                child: box,
              ),
            ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}

/// Ζητά το γραμμένο όνομα της θύρας [port]· `null` όταν ακυρωθεί, κενό =
/// καμία ετικέτα. Όταν το όνομα τελειώνει σε αριθμό, προσφέρει να συνεχίσει
/// το μοτίβο στις επόμενες κενές θύρες της συσκευής ([ports]).
///
/// Το [clashOf] βρίσκει ποια άλλη θύρα του κτιρίου έχει ήδη ένα όνομα: τότε
/// εμφανίζεται προειδοποίηση, χωρίς να εμποδίζει την αποθήκευση.
Future<({String name, bool continuePattern})?> showFloorPlanWrittenNameDialog(
  BuildContext context, {
  required String portName,
  required FloorPlanPort port,
  required List<FloorPlanPort> ports,
  FloorPlanWrittenPortName? Function(String name)? clashOf,
}) => showDialog<({String name, bool continuePattern})>(
  context: context,
  builder: (context) => _WrittenNameDialog(
    portName: portName,
    port: port,
    ports: ports,
    clashOf: clashOf,
  ),
);

class _WrittenNameDialog extends StatefulWidget {
  const _WrittenNameDialog({
    required this.portName,
    required this.port,
    required this.ports,
    this.clashOf,
  });

  final String portName;
  final FloorPlanPort port;
  final List<FloorPlanPort> ports;
  final FloorPlanWrittenPortName? Function(String name)? clashOf;

  @override
  State<_WrittenNameDialog> createState() => _WrittenNameDialogState();
}

class _WrittenNameDialogState extends State<_WrittenNameDialog> {
  late final _text = TextEditingController(text: widget.port.writtenName ?? '')
    ..addListener(() => setState(() {}));
  bool _continue = false;

  void _submit() =>
      Navigator.of(context).pop((name: _text.text, continuePattern: _continue));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Γραμμένο όνομα'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Θύρα ${widget.portName}'),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ό,τι γράφει η ετικέτα (π.χ. «Κάμερα 7»)',
              ),
              onSubmitted: (_) => _submit(),
            ),
            ?_clashWarning(context),
            ..._pattern(context),
          ],
        ),
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

  /// Η προειδοποίηση όταν το όνομα το έχει ήδη άλλη θύρα του κτιρίου.
  Widget? _clashWarning(BuildContext context) {
    final name = _text.text.trim();
    final clash = name.isEmpty ? null : widget.clashOf?.call(name);
    if (clash == null) return null;
    return _Warning(floorPlanWrittenNameWarning(name, clash));
  }

  /// Το κουτάκι «Συνέχεια στις επόμενες θύρες», μόνο όταν υπάρχει μοτίβο και
  /// θύρες μετά από αυτήν.
  List<Widget> _pattern(BuildContext context) {
    final seed = _text.text.trim();
    if (floorPlanPatternName(seed, 1) == null) return const [];
    final plan = floorPlanPatternFill(
      seed: seed,
      from: widget.port,
      ports: widget.ports,
    );
    if (plan.fill.isEmpty && plan.kept == 0) return const [];
    final first = plan.fill.isEmpty ? null : plan.fill.first;
    final last = plan.fill.isEmpty ? null : plan.fill.last;
    final summary = first == null
        ? 'Όλες οι επόμενες θύρες έχουν ήδη όνομα.'
        : [
            first == last
                ? 'Θύρα ${first.port.number}: ${first.name}'
                : 'Θύρες ${first.port.number}–${last!.port.number}: '
                      '${first.name} … ${last.name}',
            if (plan.kept > 0)
              plan.kept == 1
                  ? '1 έχει ήδη όνομα και μένει όπως είναι'
                  : '${plan.kept} έχουν ήδη όνομα και μένουν όπως είναι',
          ].join(' · ');
    final clashing = [
      for (final f in plan.fill)
        if (widget.clashOf?.call(f.name) != null) f.name,
    ];
    return [
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Συνέχεια στις επόμενες θύρες'),
        subtitle: Text(summary),
        value: _continue && first != null,
        onChanged: first == null
            ? null
            : (v) => setState(() => _continue = v ?? false),
      ),
      if (clashing.isNotEmpty)
        _Warning(
          clashing.length == 1
              ? 'Το νέο όνομα «${clashing.single}» υπάρχει ήδη αλλού.'
              : '${clashing.length} από τα νέα ονόματα υπάρχουν ήδη αλλού: '
                    '${clashing.take(5).join(', ')}'
                    '${clashing.length > 5 ? ' …' : ''}.',
        ),
    ];
  }
}

/// Προειδοποίηση κάτω από ένα πεδίο: δεν εμποδίζει, μόνο ενημερώνει.
class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
