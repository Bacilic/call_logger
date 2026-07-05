part of 'equipment_form_dialog.dart';

mixin EquipmentFormRemoteParamsMixin on EquipmentFormDialogStateHost {
  void _initRemoteParamsFromEquipment(EquipmentModel? e) {
    _remoteParamValues.clear();
    _expandedRemoteKeys.clear();
    _exclusiveRemoteToolId = null;
    if (e == null) return;
    _exclusiveRemoteToolId =
        EquipmentRemoteParamKey.exclusiveToolIdFrom(e.remoteParams);
    final nonStashEntries = <MapEntry<String, String>>[];
    final stashEntries = <MapEntry<String, String>>[];
    for (final entry in e.remoteParams.entries) {
      if (EquipmentRemoteParamKey.isReservedKey(entry.key)) continue;
      final t = entry.value.trim();
      if (t.isEmpty) continue;
      final real = EquipmentRemoteParamKey.remoteParamStashRealKeyOrNull(
        entry.key,
      );
      if (real != null) {
        stashEntries.add(MapEntry(real, entry.value));
      } else {
        nonStashEntries.add(entry);
      }
    }
    for (final entry in nonStashEntries) {
      _remoteParamValues[entry.key] = entry.value;
      _expandedRemoteKeys.add(entry.key);
    }
    for (final entry in stashEntries) {
      final k = entry.key;
      if (_expandedRemoteKeys.contains(k)) continue;
      _remoteParamValues[k] = entry.value;
    }
  }

  RemoteTool? _toolForParamKey(String key, List<RemoteTool> catalog) {
    final id = int.tryParse(key);
    if (id == null) return null;
    for (final t in catalog) {
      if (t.id == id) return t;
    }
    return null;
  }

  bool _isVncLikeParamKey(String key, List<RemoteTool> catalog) =>
      _toolForParamKey(key, catalog)?.role == ToolRole.vnc;

  void _pruneUnknownRemoteParamKeys(List<RemoteTool> catalog) {
    for (final k in _expandedRemoteKeys.toList()) {
      if (_toolForParamKey(k, catalog) == null) {
        _expandedRemoteKeys.remove(k);
        _remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
    for (final k in _remoteParamValues.keys.toList()) {
      if (EquipmentRemoteParamKey.isReservedKey(k)) continue;
      if (int.tryParse(k) == null) {
        _remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
  }

  Future<void> _pruneRemoteParamsAfterCatalogLoad() async {
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    final pairs = await widget.ref.read(remoteToolFormPairsProvider.future);
    final catalog = await widget.ref.read(remoteToolsCatalogProvider.future);
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    _didPruneUnknownRemoteKeys = true;
    setState(() {
      _pruneUnknownRemoteParamKeys(catalog);
      _recomputeDefaultRemoteFromChips(pairs, catalog);
      _tryCaptureFormBaseline();
    });
  }

  void _ensureRemoteController(String key) {
    if (_remoteParamControllers.containsKey(key)) return;
    _remoteParamControllers[key] = TextEditingController(
      text: _remoteParamValues[key] ?? '',
    );
  }

  void _disposeRemoteController(String key) {
    final c = _remoteParamControllers.remove(key);
    c?.dispose();
  }

  void _syncRemoteValueFromController(String key) {
    final c = _remoteParamControllers[key];
    if (c == null) return;
    final t = c.text.trim();
    if (t.isEmpty) {
      _remoteParamValues.remove(key);
    } else {
      _remoteParamValues[key] = c.text;
    }
  }
  void _recomputeDefaultRemoteFromChips(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final selected = <RemoteTool>[];
    for (final p in pairs) {
      if (!_expandedRemoteKeys.contains(p.key)) continue;
      final id = int.tryParse(p.key);
      if (id == null) continue;
      for (final c in catalog) {
        if (c.id == id) {
          selected.add(c);
          break;
        }
      }
    }
    selected.sort((a, b) {
      final cmp = a.sortOrder.compareTo(b.sortOrder);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });
    _defaultRemoteToolId = selected.isEmpty ? null : selected.first.id;
  }
  static const Duration _remoteAnimDuration = Duration(milliseconds: 240);

  Widget _buildRemoteParamsChipsSection(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final theme = Theme.of(context);
    if (pairs.isEmpty) {
      return Text(
        'Δεν υπάρχουν ενεργά εργαλεία απομακρυσμένης — δεν μπορείτε να επιλέξετε παραμέτρους μέσω chips.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    for (final k in _expandedRemoteKeys) {
      _ensureRemoteController(k);
    }
    final orderedExpanded = <String>[];
    final seen = <String>{};
    for (final p in pairs) {
      if (_expandedRemoteKeys.contains(p.key) && seen.add(p.key)) {
        orderedExpanded.add(p.key);
      }
    }
    for (final k in _expandedRemoteKeys) {
      if (!seen.contains(k)) {
        orderedExpanded.add(k);
        seen.add(k);
      }
    }
    String labelForKey(String key) {
      for (final p in pairs) {
        if (p.key == key) return p.label;
      }
      return key;
    }
    final defaultLabel = _defaultRemoteToolId == null
        ? 'Κανένα'
        : () {
            for (final c in catalog) {
              if (c.id == _defaultRemoteToolId) return c.name;
            }
            return '#$_defaultRemoteToolId';
          }();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Παράμετροι απομακρυσμένης',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Προεπιλεγμένο εργαλείο (πρώτο κατά σειρά ταξινόμησης μεταξύ επιλεγμένων): $defaultLabel',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (orderedExpanded.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            key: ValueKey(
              'exclusive-${_exclusiveRemoteToolId ?? 'none'}-${orderedExpanded.join(',')}',
            ),
            initialValue: _exclusiveRemoteToolId != null &&
                    _expandedRemoteKeys.contains('$_exclusiveRemoteToolId')
                ? _exclusiveRemoteToolId
                : null,
            decoration: const InputDecoration(
              labelText: 'Αποκλειστικό εργαλείο (μόνο αυτό στην κλήση)',
              helperText:
                  'Εκκαθάριση θορύβου: στην κλήση εμφανίζεται μόνο αυτό το εργαλείο για τον συγκεκριμένο εξοπλισμό.',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Κανένα'),
              ),
              for (final key in orderedExpanded)
                DropdownMenuItem<int?>(
                  value: int.tryParse(key),
                  child: Text(labelForKey(key)),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _exclusiveRemoteToolId = v;
              });
              _tryCaptureFormBaseline();
            },
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in pairs)
              FilterChip(
                label: Text(p.label),
                selected: _expandedRemoteKeys.contains(p.key),
                showCheckmark: true,
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _expandedRemoteKeys.add(p.key);
                      _ensureRemoteController(p.key);
                    } else {
                      _syncRemoteValueFromController(p.key);
                      _expandedRemoteKeys.remove(p.key);
                      _disposeRemoteController(p.key);
                      final id = int.tryParse(p.key);
                      if (id != null && id == _exclusiveRemoteToolId) {
                        _exclusiveRemoteToolId = null;
                      }
                    }
                    _recomputeDefaultRemoteFromChips(pairs, catalog);
                  });
                },
              ),
          ],
        ),
        AnimatedSize(
          duration: _remoteAnimDuration,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: orderedExpanded.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < orderedExpanded.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: _remoteAnimDuration,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.04),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey<String>(orderedExpanded[i]),
                            child: _buildRemoteParamField(
                              orderedExpanded[i],
                              labelForKey(orderedExpanded[i]),
                              pairs,
                              catalog,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRemoteParamField(
    String paramKey,
    String toolLabel,
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final c = _remoteParamControllers[paramKey];
    if (c == null) return const SizedBox.shrink();
    final isVnc = _isVncLikeParamKey(paramKey, catalog);
    final acceptsFileParam = _toolAcceptsFileParam(paramKey, pairs);
    return TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: 'Παράμετρος · $toolLabel',
        border: const OutlineInputBorder(),
        hintText: acceptsFileParam
            ? 'Αρχείο παραμέτρων πχ .rdp'
            : (isVnc ? 'IP ή hostname' : null),
      ),
      keyboardType: isVnc
          ? const TextInputType.numberWithOptions(decimal: true, signed: false)
          : TextInputType.text,
      inputFormatters:
          isVnc ? [CommaToDotDecimalSeparatorFormatter()] : null,
      onChanged: (_) => _syncRemoteValueFromController(paramKey),
    );
  }

  bool _toolAcceptsFileParam(
    String key,
    List<RemoteToolFormPair> pairs,
  ) {
    for (final p in pairs) {
      if (p.key == key) return p.acceptsFileParam;
    }
    return false;
  }
}
