import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_object_kind.dart';
import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_ports.dart';

/// Η **πρόσοψη** ενός patch panel, switch, router ή POE: κάθε θύρα στη θέση
/// της, γεμάτη όταν έχει καλώδιο, άδεια όταν είναι ελεύθερη.
///
/// Πέρασμα του ποντικιού: όνομα, γραμμένο όνομα, σύνδεση. Με
/// [onEditWrittenName] (σχεδίαση) το κλικ σε θύρα ανοίγει το «Γραμμένο
/// όνομα…».
class FloorPlanPortFacade extends StatelessWidget {
  const FloorPlanPortFacade({
    super.key,
    required this.title,
    required this.symbol,
    required this.ports,
    required this.occupied,
    required this.autoName,
    this.onEditWrittenName,
  });

  /// Π.χ. «Switch SW-2».
  final String title;
  final FloorPlanSymbol? symbol;
  final List<FloorPlanPort> ports;
  final Set<int> occupied;
  final String Function(FloorPlanPort port) autoName;
  final void Function(FloorPlanPort port)? onEditWrittenName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byNumber = {for (final p in ports) p.number: p};
    final free = ports.where((p) => !occupied.contains(p.id)).length;
    final caption = ports.isEmpty
        ? '$title · δεν έχουν δηλωθεί θύρες'
        : '$title · ${ports.length} θύρες · $free ελεύθερες';
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
            // Όλες οι θύρες ορατές χωρίς κύλιση: ως 24 ανά σειρά, και οι
            // θύρες μεγαλώνουν ή μικραίνουν με το πλάτος. Ό,τι δεν χωρά πάει
            // σε επόμενη σειρά.
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 2.0;
                final columns = floorPlanFacadeColumns(
                  constraints.maxWidth,
                  gap: gap,
                );
                final box =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                final highest = byNumber.keys.fold(0, (a, b) => a > b ? a : b);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in floorPlanFacadeRows(
                      symbol,
                      highest,
                      columns: columns,
                    ))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Row(
                          children: [
                            for (final (i, n) in row.indexed) ...[
                              if (i > 0) const SizedBox(width: gap),
                              SizedBox(
                                width: box,
                                height: 20,
                                child: byNumber[n] == null
                                    ? null
                                    : _PortBox(
                                        port: byNumber[n]!,
                                        occupied: occupied.contains(
                                          byNumber[n]!.id,
                                        ),
                                        name: autoName(byNumber[n]!),
                                        onTap: onEditWrittenName == null
                                            ? null
                                            : () => onEditWrittenName!(
                                                byNumber[n]!,
                                              ),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _PortBox extends StatelessWidget {
  const _PortBox({
    required this.port,
    required this.occupied,
    required this.name,
    this.onTap,
  });

  final FloorPlanPort port;
  final bool occupied;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final written = port.writtenName;
    final tooltip = [
      name,
      if (written != null) 'Γραμμένο: $written',
      occupied ? 'Κατειλημμένη' : 'Ελεύθερη',
      if (onTap != null) 'Κλικ: «Γραμμένο όνομα…»',
    ].join('\n');
    final box = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Γεμάτη = κατειλημμένη, άδεια = ελεύθερη — μόνο αυτό σημαίνει το
        // γέμισμα.
        color: occupied ? ink.withValues(alpha: 0.85) : null,
        border: Border.all(color: ink),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              '${port.number}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 9,
                color: occupied ? theme.colorScheme.surface : ink,
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
      child: onTap == null
          ? box
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onTap, child: box),
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

/// Ζητά το γραμμένο όνομα της θύρας· `null` όταν ακυρωθεί, κενό = καμία
/// ετικέτα.
Future<String?> showFloorPlanWrittenNameDialog(
  BuildContext context, {
  required String portName,
  String? current,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _WrittenNameDialog(portName: portName, current: current),
);

class _WrittenNameDialog extends StatefulWidget {
  const _WrittenNameDialog({required this.portName, this.current});

  final String portName;
  final String? current;

  @override
  State<_WrittenNameDialog> createState() => _WrittenNameDialogState();
}

class _WrittenNameDialogState extends State<_WrittenNameDialog> {
  late final _text = TextEditingController(text: widget.current ?? '');

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
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
