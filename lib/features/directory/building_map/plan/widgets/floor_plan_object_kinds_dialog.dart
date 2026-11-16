import 'package:flutter/material.dart';

import '../../../../../core/database/floor_plan_objects_repository.dart';
import '../../../../../core/models/floor_plan_object_kind.dart';
import 'floor_plan_symbol_painter.dart';

/// Το παράθυρο «Είδη αντικειμένων»: τα είδη που ορίζει όποιος σχεδιάζει, με
/// σύμβολο από τα έτοιμα και «έχει θύρες».
///
/// Το [floorLabel] δίνει το όνομα ενός ορόφου, για να πει το παράθυρο πού
/// βρίσκονται τα αντικείμενα ενός είδους που δεν αφαιρείται.
Future<void> showFloorPlanObjectKindsDialog(
  BuildContext context, {
  required FloorPlanObjectsRepository repository,
  required String Function(int floorId) floorLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FloorPlanObjectKindsDialog(
      repository: repository,
      floorLabel: floorLabel,
    ),
  );
}

class FloorPlanObjectKindsDialog extends StatefulWidget {
  const FloorPlanObjectKindsDialog({
    super.key,
    required this.repository,
    required this.floorLabel,
  });

  final FloorPlanObjectsRepository repository;
  final String Function(int floorId) floorLabel;

  @override
  State<FloorPlanObjectKindsDialog> createState() =>
      _FloorPlanObjectKindsDialogState();
}

class _FloorPlanObjectKindsDialogState
    extends State<FloorPlanObjectKindsDialog> {
  List<FloorPlanObjectKindUsage>? _kinds;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final kinds = await widget.repository.listKinds();
    if (!mounted) return;
    setState(() => _kinds = kinds);
  }

  String _objectsText(FloorPlanObjectKindUsage usage) {
    final floors = [for (final id in usage.floorIds) widget.floorLabel(id)]
      ..sort();
    final count = usage.objectCount == 1
        ? '1 αντικείμενο'
        : '${usage.objectCount} αντικείμενα';
    return '$count (${floors.join(', ')})';
  }

  Future<void> _add() async {
    final saved = await _showKindForm(
      context,
      title: 'Νέο είδος',
      save: (name, symbol, hasPorts, showInfo, hasNetwork) =>
          widget.repository.addKind(
            name: name,
            symbol: symbol,
            hasPorts: hasPorts,
            showInfo: showInfo,
            hasNetwork: hasNetwork,
          ),
    );
    if (saved) await _reload();
  }

  Future<void> _edit(FloorPlanObjectKind kind) async {
    final saved = await _showKindForm(
      context,
      title: 'Αλλαγή είδους',
      initial: kind,
      save: (name, symbol, hasPorts, showInfo, hasNetwork) =>
          widget.repository.updateKind(
            id: kind.id,
            name: name,
            symbol: symbol,
            hasPorts: hasPorts,
            showInfo: showInfo,
            hasNetwork: hasNetwork,
          ),
    );
    if (saved) await _reload();
  }

  Future<void> _delete(FloorPlanObjectKindUsage usage) async {
    final name = usage.kind.name;
    if (!usage.inUse) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Αφαίρεση είδους'),
          content: Text('Να αφαιρεθεί το είδος «$name»;'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Άκυρο'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Αφαίρεση'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    // Η βάση ξαναμετρά: στο μεταξύ μπορεί άλλος σταθμός να έβαλε αντικείμενο.
    final blocked = usage.inUse
        ? usage
        : await widget.repository.deleteKind(usage.kind.id);
    if (!mounted) return;
    if (blocked != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Το είδος δεν αφαιρείται'),
          content: Text(
            'Το είδος «$name» έχει ${_objectsText(blocked)}. '
            'Αφαιρέστε πρώτα τα αντικείμενά του από τον χάρτη.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Εντάξει'),
            ),
          ],
        ),
      );
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _kinds;
    return AlertDialog(
      title: const Text('Είδη αντικειμένων'),
      content: SizedBox(
        width: 520,
        height: 400,
        child: kinds == null
            ? const Center(child: CircularProgressIndicator())
            : kinds.isEmpty
            ? const Center(
                child: Text(
                  'Δεν υπάρχει ακόμη κανένα είδος.\n'
                  'Πατήστε «Νέο είδος» για να ορίσετε το πρώτο.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.separated(
                itemCount: kinds.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _row(kinds[i]),
              ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: kinds == null ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('Νέο είδος'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Κλείσιμο'),
        ),
      ],
    );
  }

  Widget _row(FloorPlanObjectKindUsage usage) {
    final kind = usage.kind;
    final details = [
      kind.symbol?.label ?? 'Σύμβολο νεότερης έκδοσης',
      if (kind.hasPorts) 'έχει θύρες',
      if (!kind.hasPorts && kind.hasNetwork) 'ασύρματο',
      if (kind.hasNetwork) 'IP / Lansweeper',
      if (!kind.showInfo) 'χωρίς πληροφορίες',
      usage.inUse ? _objectsText(usage) : 'κανένα αντικείμενο',
    ];
    return ListTile(
      leading: FloorPlanSymbolIcon(kind.symbol),
      title: Text(kind.name),
      subtitle: Text(details.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Αλλαγή',
            onPressed: () => _edit(kind),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Αφαίρεση',
            onPressed: () => _delete(usage),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// Πώς συνδέεται στο δίκτυο μια συσκευή του είδους. Δεν αποθηκεύεται ως
/// τέτοια: είναι ο συνδυασμός «έχει θύρες» και «έχει IP» (ασύρματη = χωρίς
/// θύρες, με IP).
enum _Connection {
  cable('Καλώδιο'),
  wireless('Ασύρματη'),
  none('Καμία');

  const _Connection(this.label);

  final String label;
}

typedef _SaveKind = Future<FloorPlanKindSaveOutcome> Function(
  String name,
  FloorPlanSymbol symbol,
  bool hasPorts,
  bool showInfo,
  bool hasNetwork,
);

/// Η φόρμα ενός είδους. `true` όταν γράφτηκε κάτι στη βάση.
Future<bool> _showKindForm(
  BuildContext context, {
  required String title,
  required _SaveKind save,
  FloorPlanObjectKind? initial,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _KindForm(title: title, save: save, initial: initial),
  );
  return saved ?? false;
}

class _KindForm extends StatefulWidget {
  const _KindForm({required this.title, required this.save, this.initial});

  final String title;
  final _SaveKind save;
  final FloorPlanObjectKind? initial;

  @override
  State<_KindForm> createState() => _KindFormState();
}

class _KindFormState extends State<_KindForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late FloorPlanSymbol? _symbol = widget.initial?.symbol;
  late bool _hasPorts =
      widget.initial?.hasPorts ?? (_symbol?.defaultHasPorts ?? false);
  late bool _showInfo = widget.initial?.showInfo ?? true;

  /// Νέο είδος: θύρες και IP ακολουθούν την πρόταση του συμβόλου ώσπου ο
  /// χρήστης να αγγίξει κάποιο από τα δύο. Υπάρχον είδος: όπως είναι.
  late bool _hasNetwork =
      widget.initial?.hasNetwork ?? (_symbol?.defaultHasNetwork ?? true);
  late bool _cableTouched = widget.initial != null;

  /// Το σύμβολο δείχνει τις επιλογές καλωδίου· χωρίς σύμβολο ακόμη, ναι.
  bool get _cableSettings => _symbol?.hasCableSettings ?? true;

  /// Το σύμβολο μπορεί να έχει IP· χωρίς σύμβολο ακόμη, ναι.
  bool get _networkSettings => _symbol?.canHaveNetwork ?? true;

  void _setHasPorts(bool value) => setState(() {
    _cableTouched = true;
    _hasPorts = value;
  });

  _Connection get _connection => _hasPorts
      ? _Connection.cable
      : (_hasNetwork ? _Connection.wireless : _Connection.none);

  /// Καλώδιο και ασύρματη φέρνουν IP· καμία σύνδεση, καμία διεύθυνση.
  void _setConnection(_Connection connection) => setState(() {
    _cableTouched = true;
    _hasPorts = connection == _Connection.cable;
    _hasNetwork = connection != _Connection.none;
  });

  Widget _networkTile() {
    final connection = _connection;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _hasNetwork,
      // Μόνο με καλώδιο διαλέγεται: η ασύρματη έχει πάντα IP, η «καμία»
      // ποτέ.
      onChanged: connection == _Connection.cable
          ? (v) => setState(() {
              _hasNetwork = v ?? true;
              _cableTouched = true;
            })
          : null,
      title: const Text('Έχει IP και όνομα Lansweeper'),
      subtitle: Text(switch (connection) {
        _Connection.cable =>
          'Κλειστό για συσκευή χωρίς δική της διεύθυνση, '
              'π.χ. switch χωρίς διαχείριση.',
        _Connection.wireless => 'Η ασύρματη σύνδεση έχει πάντα IP.',
        _Connection.none => 'Θέλει σύνδεση, με καλώδιο ή ασύρματη.',
      }),
    );
  }

  String? _nameError;
  String? _symbolError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    final symbol = _symbol;
    setState(() {
      _nameError = name.isEmpty ? 'Γράψτε όνομα.' : null;
      _symbolError = symbol == null ? 'Διαλέξτε σύμβολο.' : null;
    });
    if (name.isEmpty || symbol == null) return;
    setState(() => _saving = true);
    // Έπιπλο, καμπίνα, σκάλα: ποτέ καλώδιο, ποτέ IP. Patch panel, πρίζα:
    // ποτέ IP. Χωρίς καλώδιο: ποτέ IP.
    final ports = symbol.hasCableSettings && _hasPorts;
    final outcome = await widget.save(
      name,
      symbol,
      ports,
      _showInfo,
      symbol.canHaveNetwork && _hasNetwork,
    );
    if (!mounted) return;
    switch (outcome) {
      case FloorPlanKindSaveOutcome.saved:
        Navigator.pop(context, true);
      case FloorPlanKindSaveOutcome.nameTaken:
        setState(() {
          _saving = false;
          _nameError = 'Υπάρχει ήδη είδος με αυτό το όνομα.';
        });
      case FloorPlanKindSaveOutcome.missing:
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Το είδος αφαιρέθηκε στο μεταξύ από άλλον σταθμό.'),
          ),
        );
        Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      // Κυλά όταν το παράθυρο είναι χαμηλό· αλλιώς τα κάτω πεδία κόβονται.
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Όνομα',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('Σύμβολο', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final symbol in FloorPlanSymbol.forKinds)
                  ChoiceChip(
                    avatar: FloorPlanSymbolIcon(symbol, size: 24),
                    label: Text(symbol.label),
                    selected: _symbol == symbol,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _symbol = symbol;
                      _symbolError = null;
                      if (!_cableTouched) {
                        _hasPorts = symbol.defaultHasPorts;
                        _hasNetwork = symbol.defaultHasNetwork;
                      }
                    }),
                  ),
              ],
            ),
            if (_symbolError != null) ...[
              const SizedBox(height: 4),
              Text(
                _symbolError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_networkSettings) ...[
              Text('Σύνδεση', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<_Connection>(
                showSelectedIcon: false,
                segments: [
                  for (final c in _Connection.values)
                    ButtonSegment(value: c, label: Text(c.label)),
                ],
                selected: {_connection},
                onSelectionChanged: (s) => _setConnection(s.single),
              ),
              _networkTile(),
            ] else if (_cableSettings)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _hasPorts,
                onChanged: (v) => _setHasPorts(v ?? false),
                title: const Text('Έχει θύρες (συνδέεται με καλώδιο)'),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _showInfo,
              onChanged: (v) => setState(() => _showInfo = v ?? true),
              title: const Text('Δείχνει πληροφορίες με το ποντίκι'),
              subtitle: const Text(
                'Υπόδειξη στο πέρασμα και στοιχεία με κλικ· κλειστό π.χ. για '
                'έπιπλα, που είναι μέρος του χώρου.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
