import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_port.dart';
import '../floor_plan_ports.dart';

/// Ζητά θύρα patch panel: πρώτα ο όροφος της πρίζας, και σε κάθε patch panel
/// μόνο οι ελεύθερες θύρες. Επιστρέφει τη θύρα, ή `(id: null, name: null)` για
/// «Χωρίς σύνδεση»· `null` όταν ακυρωθεί.
Future<({int? id, String? name})?> showFloorPlanPatchPortDialog(
  BuildContext context, {
  required String portTitle,
  required List<FloorPlanPatchPanelGroup> groups,
  required String Function(int floorId) floorLabel,
  required bool canDisconnect,
  int? currentPortId,
}) => showDialog<({int? id, String? name})>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Σύνδεση με patch panel · $portTitle'),
    content: SizedBox(
      width: 520,
      height: 440,
      child: groups.isEmpty
          ? const Center(
              child: Text(
                'Δεν υπάρχει patch panel με ελεύθερη θύρα. Δηλώστε πρώτα '
                'θύρες σε ένα patch panel.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView(
              children: [
                for (final (i, group) in groups.indexed) ...[
                  if (i == 0 || groups[i - 1].floorId != group.floorId)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        floorLabel(group.floorId),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  _PanelPorts(group: group, currentPortId: currentPortId),
                ],
              ],
            ),
    ),
    actions: [
      if (canDisconnect)
        TextButton(
          onPressed: () => Navigator.of(context).pop((id: null, name: null)),
          child: const Text('Χωρίς σύνδεση'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Ακύρωση'),
      ),
    ],
  ),
);

class _PanelPorts extends StatelessWidget {
  const _PanelPorts({required this.group, this.currentPortId});

  final FloorPlanPatchPanelGroup group;
  final int? currentPortId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panel = group.panelName?.trim() ?? '';
    final cabinet = group.cabinetName?.trim() ?? '';
    final title = [
      if (cabinet.isNotEmpty) 'Καμπίνα $cabinet',
      panel.isEmpty ? 'Patch panel χωρίς όνομα' : 'Patch panel $panel',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final port in group.ports)
                Tooltip(
                  message: port.writtenName == null
                      ? floorPlanPatchOptionName(port)
                      : '${floorPlanPatchOptionName(port)} '
                            '(«${port.writtenName}»)',
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    label: Text('${port.number}'),
                    selected: port.portId == currentPortId,
                    onSelected: (_) => Navigator.of(context).pop((
                      id: port.portId,
                      name: floorPlanPatchOptionName(port),
                    )),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Μία συσκευή με τις ελεύθερες θύρες της, για το τέλος ενός καλωδίου. Χωρίς
/// [ports] η συσκευή έχει μία θύρα και διαλέγεται ολόκληρη.
typedef FloorPlanCableTargetGroup = ({
  int objectId,
  String title,
  List<FloorPlanPort> ports,
});

/// Ζητά πού καταλήγει το καλώδιο, όταν η συσκευή που κλικαρίστηκε έχει πολλές
/// θύρες ή η καμπίνα πολλές συσκευές. `null` όταν ακυρωθεί.
Future<({int objectId, int? portId})?> showFloorPlanCableTargetDialog(
  BuildContext context, {
  required String fromName,
  required List<FloorPlanCableTargetGroup> groups,
}) => showDialog<({int objectId, int? portId})>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('Καλώδιο από $fromName'),
    content: SizedBox(
      width: 520,
      height: 380,
      child: ListView(
        children: [
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  if (group.ports.isEmpty)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('Θύρα της συσκευής'),
                      onPressed: () =>
                          Navigator.of(context)
                              .pop((objectId: group.objectId, portId: null)),
                    )
                  else
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final port in group.ports)
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${port.number}'),
                            onPressed: () => Navigator.of(
                              context,
                            ).pop((objectId: group.objectId, portId: port.id)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Ακύρωση'),
      ),
    ],
  ),
);

/// Μία επιλογή στο «Τι είναι συνδεδεμένο»: όσες βρίσκονται στον ίδιο χώρο με
/// την πρίζα ([nearby]) έρχονται πρώτες.
typedef FloorPlanConnectionChoice = ({
  int id,
  String label,
  String? detail,
  bool nearby,
});

enum _ConnectionTab { equipment, object, text }

/// Ζητά τι είναι συνδεδεμένο σε θύρα πρίζας: εξοπλισμός του Καταλόγου,
/// αντικείμενο του χάρτη ή ελεύθερο κείμενο. Επιστρέφει τη σύνδεση με το
/// κείμενό της (κενή = τίποτα)· `null` όταν ακυρωθεί.
Future<({FloorPlanPortConnection value, String? label})?>
showFloorPlanConnectionDialog(
  BuildContext context, {
  required String portTitle,
  required FloorPlanPortConnection current,
  required List<FloorPlanConnectionChoice> equipment,
  required List<FloorPlanConnectionChoice> objects,
}) => showDialog(
  context: context,
  builder: (context) => _ConnectionDialog(
    portTitle: portTitle,
    current: current,
    equipment: equipment,
    objects: objects,
  ),
);

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({
    required this.portTitle,
    required this.current,
    required this.equipment,
    required this.objects,
  });

  final String portTitle;
  final FloorPlanPortConnection current;
  final List<FloorPlanConnectionChoice> equipment;
  final List<FloorPlanConnectionChoice> objects;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late _ConnectionTab _tab = widget.current.objectId != null
      ? _ConnectionTab.object
      : widget.current.text != null
      ? _ConnectionTab.text
      : _ConnectionTab.equipment;
  final _search = TextEditingController();
  late final _text = TextEditingController(text: widget.current.text ?? '');

  @override
  void dispose() {
    _search.dispose();
    _text.dispose();
    super.dispose();
  }

  void _pop(FloorPlanPortConnection value, String? label) =>
      Navigator.of(context).pop((value: value, label: label));

  void _commitText() {
    final value = FloorPlanPortConnection.freeText(_text.text);
    _pop(value, value.text);
  }

  Widget _list(
    List<FloorPlanConnectionChoice> choices,
    FloorPlanPortConnection Function(int id) toConnection,
    String emptyText,
  ) {
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in choices)
        if (query.isEmpty ||
            c.label.toLowerCase().contains(query) ||
            (c.detail?.toLowerCase().contains(query) ?? false))
          c,
    ];
    return Column(
      children: [
        TextField(
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Αναζήτηση',
            isDense: true,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(emptyText))
              : ListView.builder(
                  itemCount: shown.length,
                  itemExtent: 48,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    final connection = toConnection(c.id);
                    return ListTile(
                      dense: true,
                      selected: connection == widget.current,
                      leading: c.nearby
                          ? const Tooltip(
                              message: 'Στον ίδιο χώρο με την πρίζα',
                              child: Icon(Icons.place_outlined, size: 18),
                            )
                          : const SizedBox(width: 18),
                      title: Text(c.label, overflow: TextOverflow.ellipsis),
                      subtitle: c.detail == null
                          ? null
                          : Text(c.detail!, overflow: TextOverflow.ellipsis),
                      onTap: () => _pop(connection, c.label),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Τι είναι συνδεδεμένο · ${widget.portTitle}'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_ConnectionTab>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _ConnectionTab.equipment,
                  label: Text('Εξοπλισμός'),
                ),
                ButtonSegment(
                  value: _ConnectionTab.object,
                  label: Text('Αντικείμενο χάρτη'),
                ),
                ButtonSegment(
                  value: _ConnectionTab.text,
                  label: Text('Κείμενο'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() {
                _tab = s.first;
                _search.clear();
              }),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                _ConnectionTab.equipment => _list(
                  widget.equipment,
                  FloorPlanPortConnection.equipment,
                  'Δεν βρέθηκε εξοπλισμός.',
                ),
                _ConnectionTab.object => _list(
                  widget.objects,
                  FloorPlanPortConnection.object,
                  'Δεν βρέθηκε αντικείμενο σε αυτόν τον όροφο.',
                ),
                _ConnectionTab.text => Align(
                  alignment: Alignment.topCenter,
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Τι είναι συνδεδεμένο (π.χ. αναλυτής)',
                    ),
                    onSubmitted: (_) => _commitText(),
                  ),
                ),
              },
            ),
          ],
        ),
      ),
      actions: [
        if (!widget.current.isEmpty)
          TextButton(
            onPressed: () => _pop(FloorPlanPortConnection.none, null),
            child: const Text('Τίποτα συνδεδεμένο'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ακύρωση'),
        ),
        if (_tab == _ConnectionTab.text)
          FilledButton(onPressed: _commitText, child: const Text('Εντάξει')),
      ],
    );
  }
}
