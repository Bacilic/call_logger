import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/services/lansweeper_asset_page.dart';
import '../../../../../core/utils/run_after_next_frame.dart';
import '../../../../../core/widgets/compact_tooltip.dart';
import '../../../../calls/utils/vnc_remote_target.dart';
import '../../../screens/widgets/lansweeper_asset_page_button.dart';
import '../floor_plan_object_fields.dart';
import '../floor_plan_ports.dart';

/// Τα στοιχεία ενός αντικειμένου όπως τα γράφει το πλαίσιο.
typedef FloorPlanObjectDetails = ({
  String name,

  /// Το μοντέλο της συσκευής (π.χ. NWA130BE).
  String model,
  String ip,
  String lansweeperName,

  /// Ο αριθμός της σελίδας στο Lansweeper, ή ολόκληρη η διεύθυνσή της, όπως
  /// γράφτηκε — δες `parseLansweeperAssetId`.
  String lansweeperAssetId,
  String notes,

  /// Οι ομάδες θυρών όπως γράφτηκαν· κενό όταν το είδος δεν δηλώνει
  /// πλήθος θυρών.
  List<FloorPlanPortGroupDraft> portGroups,

  /// Το διαχωριστικό θυρών ενός patch panel· `null` = αυτόματο (ο χρήστης
  /// δεν το άγγιξε ποτέ), κενό = χωρίς διαχωριστικό.
  String? portSeparator,

  /// Πόσα U πιάνει μέσα στην καμπίνα όπως γράφτηκε· κενό εκτός καμπίνας.
  String heightU,
});

/// Πόσο πλατύ είναι το πλαίσιο — για να το τοποθετήσει η οθόνη.
const double kFloorPlanObjectEditorWidth = 300;

/// Πλαίσιο στοιχείων αντικειμένου πάνω στον χάρτη: όνομα, μοντέλο, IP,
/// όνομα και σελίδα Lansweeper, θύρες, σημειώσεις — με ✕ / ✓ στη μικρή μπάρα από πάνω, όπως το
/// πλαίσιο κειμένου.
///
/// Enter σε μονογραμμικό πεδίο ή Ctrl+Enter αποθηκεύει· Esc ή ✕ ακυρώνει. Το
/// κλικ έξω από το πλαίσιο το χειρίζεται η οθόνη (αποθηκεύει, αν στέκουν τα
/// πεδία). Κανένα πεδίο δεν είναι υποχρεωτικό, αλλά ό,τι γράφεται πρέπει να
/// στέκει: λάθος IP ή θύρες εκτός ορίων κρατούν το πλαίσιο ανοιχτό, με το
/// μήνυμα κάτω από το πεδίο.
class FloorPlanObjectEditor extends StatefulWidget {
  const FloorPlanObjectEditor({
    super.key,
    required this.title,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    this.network = true,
    this.portCount = false,
    this.portGroups = false,
    this.portTypes = const {},
    this.portSeparator = false,
    this.cabinetName,
    this.cabinetUnits,
    this.footer,
  });

  /// Το είδος του αντικειμένου, π.χ. «Εκτυπωτής».
  final String title;
  final FloorPlanObjectDetails initial;
  final void Function(FloorPlanObjectDetails details) onCommit;
  final VoidCallback onCancel;

  /// Δείχνει IP, όνομα και σελίδα Lansweeper — το ορίζει το είδος.
  final bool network;

  /// Δείχνει το «Μοντέλο»: μόνο στις συσκευές (με δίκτυο ή θύρες), όχι στα
  /// έπιπλα και τα σύμβολα.
  bool get _isDevice => network || portCount;

  /// Δείχνει το πεδίο «Θύρες» (patch panel, switch, router, POE).
  final bool portCount;

  /// Δείχνει ομάδες θυρών — πρόθεμα, ταχύτητα, «+ Ομάδα θυρών». Όχι στα patch
  /// panel, που έχουν πάντα μία ομάδα.
  final bool portGroups;

  /// Τα προθέματα που διαλέγονται στο «Τύπος θυρών» (switch), με την υπόδειξη
  /// που εξηγεί το καθένα· κενό = το πρόθεμα γράφεται ελεύθερα.
  final Map<String, String> portTypes;

  /// Δείχνει το «Διαχωριστικό θύρας» με την προεπισκόπησή του (patch panel).
  final bool portSeparator;

  /// Η καμπίνα όπου βρίσκεται — για την προεπισκόπηση του ονόματος θύρας.
  final String? cabinetName;

  /// Πόσα U έχει η καμπίνα όπου βρίσκεται· `null` εκτός καμπίνας, οπότε δεν
  /// φαίνεται το «Ύψος (U)».
  final int? cabinetUnits;

  /// Κάτω από τα πεδία — π.χ. η πρόσοψη με τις θύρες.
  final Widget? footer;

  @override
  State<FloorPlanObjectEditor> createState() => FloorPlanObjectEditorState();
}

class FloorPlanObjectEditorState extends State<FloorPlanObjectEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _model = TextEditingController(text: widget.initial.model);
  late final _ip = TextEditingController(text: widget.initial.ip);
  late final _lansweeper = TextEditingController(
    text: widget.initial.lansweeperName,
  );
  late final _assetId = TextEditingController(
    text: widget.initial.lansweeperAssetId,
  );
  late final _notes = TextEditingController(text: widget.initial.notes);
  late final List<_PortGroupFields> _groups = [
    for (final g in widget.initial.portGroups) _PortGroupFields(g),
    if (widget.initial.portGroups.isEmpty) _PortGroupFields.empty(),
  ];
  late final _height = TextEditingController(text: widget.initial.heightU);
  late final _separator = TextEditingController(
    text:
        widget.initial.portSeparator ??
        floorPlanDefaultPortSeparator(widget.initial.name),
  );

  /// Ο χρήστης έγραψε στο διαχωριστικό. Ώσπου να γράψει, το πεδίο δείχνει την
  /// πρόταση της εφαρμογής και την ακολουθεί όσο αλλάζει το όνομα.
  bool _separatorTouched = false;

  /// Τα μηνύματα φαίνονται μόνο μετά από απόπειρα αποθήκευσης ή από τη στιγμή
  /// που το πεδίο αλλάξει — όχι από το άνοιγμα.
  bool _showErrors = false;

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
    model: _model.text,
    ip: widget.network ? floorPlanNormalizedIp(_ip.text) : _ip.text,
    lansweeperName: _lansweeper.text,
    lansweeperAssetId: _assetId.text,
    notes: _notes.text,
    portGroups: widget.portCount
        ? [for (final g in _groups) g.draft]
        : const [],
    portSeparator: widget.portSeparator && _separatorTouched
        ? _separator.text
        : widget.initial.portSeparator,
    heightU: _height.text,
  );

  String? get _ipError => widget.network ? floorPlanIpError(_ip.text) : null;

  String? get _assetIdError =>
      widget.network ? parseLansweeperAssetId(_assetId.text).error : null;

  bool get _portsOk =>
      !widget.portCount ||
      _groups.every((g) => floorPlanPortCountError(g.count.text) == null);

  String? get _heightError => switch (widget.cabinetUnits) {
    final units? => floorPlanHeightUError(_height.text, units),
    null => null,
  };

  /// Στέκουν όλα τα πεδία; Αν όχι, δείχνει τα μηνύματα και το πλαίσιο μένει
  /// ανοιχτό — το ρωτά και η οθόνη πριν αποθηκεύσει με κλικ έξω.
  bool validate() {
    final ok =
        _ipError == null &&
        _assetIdError == null &&
        _portsOk &&
        _heightError == null;
    if (!ok) setState(() => _showErrors = true);
    return ok;
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _ip.dispose();
    _lansweeper.dispose();
    _assetId.dispose();
    _notes.dispose();
    for (final g in _groups) {
      g.dispose();
    }
    _height.dispose();
    _separator.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _commit() {
    if (validate()) widget.onCommit(current);
  }

  void _onNameChanged(String name) {
    if (!widget.portSeparator) return;
    setState(() {
      if (!_separatorTouched && widget.initial.portSeparator == null) {
        _separator.text = floorPlanDefaultPortSeparator(name);
      }
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    FocusNode? focusNode,
    bool multiline = false,
    bool digits = false,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? error,
    String? helper,
    Widget? suffix,
    ValueChanged<String>? onChanged,
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
            : (keyboardType ?? (digits ? TextInputType.number : null)),
        inputFormatters: [
          if (digits) FilteringTextInputFormatter.digitsOnly,
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
          ...?inputFormatters,
        ],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          errorText: _showErrors ? error : null,
          errorMaxLines: 2,
          helperText: helper,
          helperMaxLines: 2,
          suffixIcon: suffix,
        ),
        onChanged: (value) {
          onChanged?.call(value);
          // Ό,τι διορθώνεται, ξανακρίνεται αμέσως.
          if (_showErrors) setState(() {});
        },
        onSubmitted: multiline ? null : (_) => _commit(),
      ),
    );
  }

  /// Η σελίδα στο Lansweeper: δέχεται τον αριθμό ή ολόκληρη τη διεύθυνση, και
  /// μόλις βγει αριθμός δείχνει το κουμπί που την ανοίγει.
  Widget _assetIdField() {
    final id = parseLansweeperAssetId(_assetId.text).id;
    return _field(
      _assetId,
      'Σελίδα Lansweeper (AssetID)',
      helper: id == null ? 'Επικολλήστε τη διεύθυνση της σελίδας' : null,
      error: _assetIdError,
      suffix: id == null ? null : LansweeperAssetPageButton(assetId: id),
      // Το κουμπί εμφανίζεται με το πρώτο έγκυρο γράμμα.
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _separatorField() {
    final preview = floorPlanPortSeparatorPreview(
      panelName: _name.text,
      cabinetName: widget.cabinetName,
      separator: _separator.text,
    );
    return _field(
      _separator,
      'Διαχωριστικό θύρας',
      maxLength: kFloorPlanPortSeparatorMaxLength,
      helper: 'Θύρα 1 → $preview',
      onChanged: (_) => setState(() => _separatorTouched = true),
    );
  }

  /// Οι ομάδες θυρών: για καθεμιά πλήθος, πρόθεμα και ταχύτητα· από τη
  /// δεύτερη και μετά, «συνεχίζει» και αφαίρεση. Στο patch panel μόνο το
  /// πλήθος, όπως πάντα.
  List<Widget> _portGroupsSection(ThemeData theme) {
    if (!widget.portGroups) {
      return [
        _field(
          _groups.first.count,
          'Θύρες (πλήθος)',
          digits: true,
          maxLength: 3,
          error: floorPlanPortCountError(_groups.first.count.text),
        ),
      ];
    }
    final several = _groups.length > 1;
    return [
      for (final (i, g) in _groups.indexed) ...[
        if (several) _portGroupHeader(theme, i, g),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                g.count,
                // Δίπλα στο πρόθεμα και την ταχύτητα το «(πλήθος)» δεν χωρά.
                'Θύρες',
                digits: true,
                maxLength: 3,
                error: floorPlanPortCountError(g.count.text),
              ),
            ),
            if (widget.portTypes.isEmpty) ...[
              const SizedBox(width: 6),
              Expanded(child: _field(g.prefix, 'Πρόθεμα', maxLength: 6)),
            ],
            const SizedBox(width: 6),
            Expanded(flex: 2, child: _field(g.speed, 'Ταχύτητα')),
          ],
        ),
        if (widget.portTypes.isNotEmpty) _portTypeChooser(theme, g),
      ],
      if (_groups.length < kFloorPlanMaxPortGroups)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => _groups.add(_PortGroupFields.empty())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ομάδα θυρών'),
          ),
        ),
    ];
  }

  Widget _portGroupHeader(ThemeData theme, int i, _PortGroupFields g) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ομάδα ${i + 1}',
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (i > 0) ...[
            CompactTooltip(
              message:
                  'Ίδιος μεσαίος αριθμός με την προηγούμενη ομάδα, και η '
                  'αρίθμηση συνεχίζει (π.χ. Te1/0/8 → Gi1/0/9).',
              child: InkWell(
                onTap: () => setState(() => g.continues = !g.continues),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: g.continues,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) =>
                          setState(() => g.continues = v ?? false),
                    ),
                    Text('συνεχίζει', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Αφαίρεση ομάδας',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _groups.removeAt(i).dispose()),
              icon: const Icon(Icons.remove_circle_outline, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portTypeChooser(ThemeData theme, _PortGroupFields g) {
    final selected = g.prefix.text.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('Τύπος θυρών', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Expanded(
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final MapEntry(key: t, value: help)
                    in widget.portTypes.entries)
                  ButtonSegment(value: t, label: Text(t), tooltip: help),
              ],
              selected: {if (selected.isNotEmpty) selected},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) {
                if (s.isNotEmpty) setState(() => g.prefix.text = s.first);
              },
            ),
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
                      _field(
                        _name,
                        'Όνομα',
                        focusNode: _nameFocus,
                        onChanged: _onNameChanged,
                      ),
                      if (widget._isDevice) _field(_model, 'Μοντέλο'),
                      if (widget.portSeparator) _separatorField(),
                      if (widget.network) ...[
                        _field(
                          _ip,
                          'IP',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          // Η «τελεία» του αριθμητικού πληκτρολογίου έρχεται
                          // ως κόμμα στο ελληνικό· στην IP γίνεται τελεία.
                          inputFormatters: [
                            CommaToDotDecimalSeparatorFormatter(),
                          ],
                          error: _ipError,
                        ),
                        _field(_lansweeper, 'Όνομα Lansweeper'),
                        _assetIdField(),
                      ],
                      if (widget.portCount) ..._portGroupsSection(theme),
                      if (widget.cabinetUnits != null)
                        _field(
                          _height,
                          'Ύψος (U)',
                          digits: true,
                          maxLength: 3,
                          error: _heightError,
                        ),
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

/// Τα πεδία μιας ομάδας θυρών μέσα στη φόρμα.
class _PortGroupFields {
  _PortGroupFields(FloorPlanPortGroupDraft initial)
    : source = initial.source,
      count = TextEditingController(text: initial.count),
      prefix = TextEditingController(text: initial.prefix),
      speed = TextEditingController(text: initial.speed),
      continues = initial.continues;

  /// Νέα ομάδα, χωρίς θύρες ακόμη.
  _PortGroupFields.empty()
    : this((source: null, count: '', prefix: '', speed: '', continues: false));

  final int? source;
  final TextEditingController count;
  final TextEditingController prefix;
  final TextEditingController speed;
  bool continues;

  FloorPlanPortGroupDraft get draft => (
    source: source,
    count: count.text,
    prefix: prefix.text,
    speed: speed.text,
    continues: continues,
  );

  void dispose() {
    count.dispose();
    prefix.dispose();
    speed.dispose();
  }
}
