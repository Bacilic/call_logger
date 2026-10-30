import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/utils/run_after_next_frame.dart';

/// Τα στοιχεία ενός αντικειμένου όπως τα γράφει το πλαίσιο.
typedef FloorPlanObjectDetails = ({
  String name,
  String ip,
  String lansweeperName,
  String notes,

  /// Πλήθος θυρών όπως γράφτηκε· κενό όταν το είδος δεν έχει θύρες.
  String portCount,
});

/// Πόσο πλατύ είναι το πλαίσιο — για να το τοποθετήσει η οθόνη.
const double kFloorPlanObjectEditorWidth = 300;

/// Πλαίσιο στοιχείων αντικειμένου πάνω στον χάρτη: όνομα, IP, όνομα
/// Lansweeper, σημειώσεις — με ✕ / ✓ στη μικρή μπάρα από πάνω, όπως το
/// πλαίσιο κειμένου.
///
/// Enter σε μονογραμμικό πεδίο ή Ctrl+Enter αποθηκεύει· Esc ή ✕ ακυρώνει. Το
/// κλικ έξω από το πλαίσιο το χειρίζεται η οθόνη (αποθηκεύει). Κανένα πεδίο
/// δεν είναι υποχρεωτικό. Το έπιπλο ([volume]) δείχνει μόνο όνομα και
/// σημειώσεις: IP και Lansweeper δεν έχουν νόημα για ένα γραφείο.
class FloorPlanObjectEditor extends StatefulWidget {
  const FloorPlanObjectEditor({
    super.key,
    required this.title,
    required this.volume,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    this.portCount = false,
    this.footer,
  });

  /// Το είδος του αντικειμένου, π.χ. «Εκτυπωτής».
  final String title;
  final bool volume;
  final FloorPlanObjectDetails initial;
  final void Function(FloorPlanObjectDetails details) onCommit;
  final VoidCallback onCancel;

  /// Δείχνει το πεδίο «Θύρες» (patch panel, switch, router, POE).
  final bool portCount;

  /// Κάτω από τα πεδία — π.χ. η πρόσοψη με τις θύρες.
  final Widget? footer;

  @override
  State<FloorPlanObjectEditor> createState() => FloorPlanObjectEditorState();
}

class FloorPlanObjectEditorState extends State<FloorPlanObjectEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _ip = TextEditingController(text: widget.initial.ip);
  late final _lansweeper = TextEditingController(
    text: widget.initial.lansweeperName,
  );
  late final _notes = TextEditingController(text: widget.initial.notes);
  late final _ports = TextEditingController(text: widget.initial.portCount);

  /// Το «Όνομα» ζητά ρητά την εστίαση: ο καμβάς την κρατά όταν ανοίγει το
  /// πλαίσιο, και το σκέτο `autofocus` δεν την παίρνει από κάτι που ήδη την
  /// έχει — τα γράμματα πήγαιναν στον καμβά.
  final FocusNode _nameFocus = FocusNode(debugLabel: 'floor-plan-object-name');

  @override
  void initState() {
    super.initState();
    runAfterNextFrame(() {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  /// Ό,τι γράφει αυτή τη στιγμή το πλαίσιο — για αποθήκευση από έξω.
  FloorPlanObjectDetails get current => (
    name: _name.text,
    ip: _ip.text,
    lansweeperName: _lansweeper.text,
    notes: _notes.text,
    portCount: _ports.text,
  );

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _lansweeper.dispose();
    _notes.dispose();
    _ports.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _commit() => widget.onCommit(current);

  Widget _field(
    TextEditingController controller,
    String label, {
    FocusNode? focusNode,
    bool multiline = false,
    bool digits = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: multiline ? 3 : 1,
        minLines: 1,
        keyboardType: multiline
            ? TextInputType.multiline
            : (digits ? TextInputType.number : null),
        inputFormatters: digits
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: multiline ? null : (_) => _commit(),
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
        width: kFloorPlanObjectEditorWidth,
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
                      _field(_name, 'Όνομα', focusNode: _nameFocus),
                      if (!widget.volume) ...[
                        _field(_ip, 'IP'),
                        _field(_lansweeper, 'Όνομα Lansweeper'),
                      ],
                      if (widget.portCount)
                        _field(_ports, 'Θύρες (πλήθος)', digits: true),
                      _field(_notes, 'Σημειώσεις', multiline: true),
                      if (widget.footer case final footer?) ...[
                        const SizedBox(height: 12),
                        footer,
                      ],
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
