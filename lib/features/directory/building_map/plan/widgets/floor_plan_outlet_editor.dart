import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/utils/run_after_next_frame.dart';
import '../floor_plan_ports.dart';

/// Πόσο πλατύ είναι το πλαίσιο της πρίζας — για να το τοποθετήσει η οθόνη.
const double kFloorPlanOutletEditorWidth = 400;

/// Πλαίσιο πρίζας πάνω στον χάρτη: μία ή δύο θύρες, κάθε μία με τη σύνδεσή της
/// στο patch panel, το γραμμένο όνομα και το τι είναι συνδεδεμένο.
///
/// Τίποτα δεν γράφεται πριν από το ✓: Enter ή Ctrl+Enter αποθηκεύει, Esc ή ✕
/// ακυρώνει όλες τις αλλαγές του πλαισίου. Το κλικ έξω από το πλαίσιο το
/// χειρίζεται η οθόνη (αποθηκεύει).
class FloorPlanOutletEditor extends StatefulWidget {
  const FloorPlanOutletEditor({
    super.key,
    required this.title,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    required this.onPickPatchPort,
    required this.onPickConnection,
  });

  /// Το είδος του αντικειμένου, π.χ. «Πρίζα».
  final String title;

  /// Οι θύρες όπως είναι τώρα, με τη σειρά των αριθμών τους.
  final List<FloorPlanOutletPortDraft> initial;
  final void Function(List<FloorPlanOutletPortDraft> ports) onCommit;
  final VoidCallback onCancel;

  /// Ζητά θύρα patch panel για το [port]· `null` = δεν άλλαξε τίποτα. Το
  /// [others] είναι όσες κρατά ήδη η άλλη θύρα της πλάκας.
  final Future<({int? id, String? name})?> Function(
    FloorPlanOutletPortDraft port,
    Set<int> others,
  )
  onPickPatchPort;

  /// Ζητά τι είναι συνδεδεμένο στο [port]· `null` = δεν άλλαξε τίποτα.
  final Future<FloorPlanOutletPortDraft?> Function(
    FloorPlanOutletPortDraft port,
  )
  onPickConnection;

  @override
  State<FloorPlanOutletEditor> createState() => FloorPlanOutletEditorState();
}

class FloorPlanOutletEditorState extends State<FloorPlanOutletEditor> {
  /// Κρατιούνται και οι δύο θύρες όσο είναι ανοιχτό το πλαίσιο, ώστε το
  /// γύρισμα 2 → 1 → 2 να μη χάνει ό,τι γράφτηκε.
  late final Map<int, FloorPlanOutletPortDraft> _ports = {
    for (final n in const [1, 2]) n: FloorPlanOutletPortDraft(number: n),
    for (final p in widget.initial) p.number: p,
  };
  late final Map<int, TextEditingController> _written = {
    for (final MapEntry(:key, :value) in _ports.entries)
      key: TextEditingController(text: value.writtenName ?? ''),
  };
  late int _count = widget.initial.length;

  /// Ο καμβάς κρατά την εστίαση όταν ανοίγει το πλαίσιο· χωρίς ρητό αίτημα το
  /// Esc και τα γράμματα θα πήγαιναν εκεί.
  final FocusNode _firstField = FocusNode(debugLabel: 'floor-plan-outlet');

  @override
  void initState() {
    super.initState();
    runAfterNextFrame(() {
      if (mounted) _firstField.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _written.values) {
      c.dispose();
    }
    _firstField.dispose();
    super.dispose();
  }

  /// Ό,τι γράφει αυτή τη στιγμή το πλαίσιο — για αποθήκευση από έξω.
  List<FloorPlanOutletPortDraft> get current => [
    for (var n = 1; n <= _count; n++)
      _ports[n]!.copyWith(writtenName: () => _written[n]!.text),
  ];

  void _commit() => widget.onCommit(current);

  Future<void> _pickPatchPort(int number) async {
    final others = {
      for (final p in current)
        if (p.number != number) ?p.patchPortId,
    };
    final picked = await widget.onPickPatchPort(_ports[number]!, others);
    if (picked == null || !mounted) return;
    setState(() {
      _ports[number] = _ports[number]!.copyWith(patchPort: picked);
    });
  }

  Future<void> _pickConnection(int number) async {
    final picked = await widget.onPickConnection(_ports[number]!);
    if (picked == null || !mounted) return;
    setState(() => _ports[number] = picked);
  }

  Widget _portRow(BuildContext context, int number) {
    final theme = Theme.of(context);
    final port = _ports[number]!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Θύρα $number', style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _pickPatchPort(number),
                  icon: const Icon(Icons.cable, size: 18),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      port.patchPortName ?? kFloorPlanOutletUnlinked,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _written[number],
            focusNode: number == 1 ? _firstField : null,
            decoration: const InputDecoration(
              labelText: 'Γραμμένο όνομα',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _commit(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Συνδεδεμένο: ${port.connectionLabel ?? 'τίποτα'}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Τι είναι συνδεδεμένο',
                visualDensity: VisualDensity.compact,
                onPressed: () => _pickConnection(number),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _commit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _commit,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: SizedBox(
        width: kFloorPlanOutletEditorWidth,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ακύρωση (Esc)',
                      onPressed: widget.onCancel,
                      icon: Icon(Icons.close, color: theme.colorScheme.error),
                    ),
                    IconButton(
                      tooltip: 'Αποθήκευση (Enter)',
                      onPressed: _commit,
                      icon: const Icon(Icons.check, color: Colors.green),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<int>(
                        emptySelectionAllowed: true,
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1 θύρα')),
                          ButtonSegment(value: 2, label: Text('2 θύρες')),
                        ],
                        selected: {if (_count > 0) _count},
                        onSelectionChanged: (s) {
                          if (s.isNotEmpty) setState(() => _count = s.first);
                        },
                      ),
                      for (var n = 1; n <= _count; n++) _portRow(context, n),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
