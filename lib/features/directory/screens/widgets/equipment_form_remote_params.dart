part of 'equipment_form_dialog.dart';

mixin EquipmentFormRemoteParamsMixin on EquipmentFormDialogStateHost {
  void _initRemoteParamsFromEquipment(EquipmentModel? e) {
    _remoteParamValues.clear();
    _expandedRemoteKeys.clear();
    _exclusiveRemoteToolId = null;
    if (e == null) return;
    _exclusiveRemoteToolId =
        EquipmentRemoteParamKey.exclusiveToolIdFrom(e.remoteParams);
    // Φόρτωσε όλες τις τιμές (και τις ιστορικές `__stash_`) κάτω από το πραγματικό
    // κλειδί `<tool_id>`· οι ενεργές τιμές υπερισχύουν των ιστορικών.
    for (final entry in e.remoteParams.entries) {
      if (entry.key == EquipmentRemoteParamKey.exclusiveToolKey) continue;
      final stashReal =
          EquipmentRemoteParamKey.remoteParamStashRealKeyOrNull(entry.key);
      final realKey = stashReal ?? entry.key;
      if (int.tryParse(realKey) == null) continue;
      if (stashReal != null && _remoteParamValues.containsKey(realKey)) {
        continue;
      }
      _remoteParamValues[realKey] = entry.value;
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

  Future<void> _pruneRemoteParamsAfterCatalogLoad() async {
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    final pairs = await widget.ref.read(remoteToolFormPairsProvider.future);
    if (!mounted || _didPruneUnknownRemoteKeys) return;
    _didPruneUnknownRemoteKeys = true;
    setState(() {
      _syncRemoteParamsToForm(pairs);
      _tryCaptureFormBaseline();
    });
  }

  /// Κάθε εργαλείο της φόρμας έχει πεδίο (κλειδί = `<tool_id>`). Καθαρίζει τιμές
  /// που δεν αντιστοιχούν σε εργαλείο της φόρμας και ακυρώνει άκυρο αποκλειστικό.
  void _syncRemoteParamsToForm(List<RemoteToolFormPair> pairs) {
    final formKeys = {for (final p in pairs) p.key};
    for (final k in _remoteParamValues.keys.toList()) {
      if (!formKeys.contains(k)) {
        _remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
    _expandedRemoteKeys
      ..clear()
      ..addAll(formKeys);
    for (final k in _expandedRemoteKeys) {
      _ensureRemoteController(k);
    }
    if (_exclusiveRemoteToolId != null &&
        !formKeys.contains('$_exclusiveRemoteToolId')) {
      _exclusiveRemoteToolId = null;
    }
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

  Widget _buildRemoteParamsSection(
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog,
  ) {
    final theme = Theme.of(context);
    if (pairs.isEmpty) {
      return Text(
        'Δεν υπάρχουν ενεργά εργαλεία απομακρυσμένης σύνδεσης.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    // Σειρά προτεραιότητας: τα `pairs` έρχονται ήδη ταξινομημένα (sort_order).
    // Αποδίδουμε απευθείας από τα `pairs` ώστε τα πεδία/επιλογές να υπάρχουν και
    // πριν ολοκληρωθεί το async prune (που συγχρονίζει το `_expandedRemoteKeys`).
    final orderedKeys = <String>[];
    final seen = <String>{};
    for (final p in pairs) {
      if (seen.add(p.key)) {
        orderedKeys.add(p.key);
        _ensureRemoteController(p.key);
      }
    }
    String labelForKey(String key) {
      for (final p in pairs) {
        if (p.key == key) return p.label;
      }
      return key;
    }

    RemoteTool? toolForId(int id) {
      for (final t in catalog) {
        if (t.id == id) return t;
      }
      return null;
    }

    final exclusiveValid = _exclusiveRemoteToolId != null &&
        toolForId(_exclusiveRemoteToolId!) != null;
    final int? zoneAValue = exclusiveValid ? _exclusiveRemoteToolId : null;

    // Ζώνη Α — προειδοποίηση όταν το «μόνο» εργαλείο χρειάζεται παράμετρο και είναι κενή.
    String? warning;
    if (zoneAValue != null) {
      final selTool = toolForId(zoneAValue);
      final selParam = (_remoteParamControllers['$zoneAValue']?.text ?? '').trim();
      if (selTool != null &&
          selParam.isEmpty &&
          (selTool.role == ToolRole.rdp || selTool.role == ToolRole.anydesk)) {
        warning =
            'Το «${selTool.name}» χρειάζεται παράμετρο, αλλιώς δεν θα εμφανιστεί στην κλήση.';
      }
    }

    // Ζώνη Β — πεδία παραμέτρων, με κρύψιμο/γκριζάρισμα όταν έχει επιλεγεί ένα μόνο εργαλείο.
    final rows = <Widget>[];
    for (final key in orderedKeys) {
      final isSelectedOnly = zoneAValue != null && key == '$zoneAValue';
      if (zoneAValue != null && !isSelectedOnly) {
        final hasValue = (_remoteParamValues[key] ?? '').trim().isNotEmpty;
        if (!hasValue) continue; // κενή παράμετρος άλλου εργαλείου → κρύψε
        rows.add(
          _buildRemoteParamField(
            key,
            pairs,
            catalog,
            disabled: true,
            historical: true,
          ),
        );
      } else {
        rows.add(
          _buildRemoteParamField(key, pairs, catalog),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Εμφάνιση στην κλήση: Επιλέξτε «Όλα» ή ένα μόνο εργαλείο για αυτόν τον εξοπλισμό.', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          key: ValueKey('zoneA-${zoneAValue ?? 'all'}'),
          initialValue: zoneAValue,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Όλα τα εργαλεία'),
            ),
            for (final key in orderedKeys)
              DropdownMenuItem<int?>(
                value: int.tryParse(key),
                child: Text('Μόνο: ${labelForKey(key)}'),
              ),
          ],
          onChanged: (v) {
            setState(() => _exclusiveRemoteToolId = v);
            _tryCaptureFormBaseline();
          },
        ),
        if (warning != null) ...[
          const SizedBox(height: 8),
          _buildRemoteWarning(theme, warning),
        ],
        const SizedBox(height: 16),
        Text('Παράμετροι ανά εργαλείο', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Εμφανίζονται με σειρά προτεραιότητας. Αφήστε κενό για απενεργοποίηση — το VNC κρατά τον προεπιλεγμένο στόχο (PC + κωδικός).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }

  Widget _buildRemoteWarning(ThemeData theme, String message) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: cs.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteParamField(
    String paramKey,
    List<RemoteToolFormPair> pairs,
    List<RemoteTool> catalog, {
    bool disabled = false,
    bool historical = false,
  }) {
    final c = _remoteParamControllers[paramKey];
    if (c == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isVnc = _isVncLikeParamKey(paramKey, catalog);
    final acceptsFileParam = _toolAcceptsFileParam(paramKey, pairs);
    final tool = _toolForParamKey(paramKey, catalog);
    final hasIcon = tool?.iconAssetKey?.trim().isNotEmpty ?? false;
    final roleLabel = switch (tool?.role) {
      ToolRole.anydesk => 'Κωδικός AnyDesk',
      ToolRole.rdp when acceptsFileParam => 'Αρχείο σύνδεσης (.rdp)',
      ToolRole.vnc || ToolRole.rdp => 'Διεύθυνση (IP ή όνομα υπολογιστή)',
      _ => 'Στόχος σύνδεσης',
    };
    final labelText = _remoteParamLabelWithTool(tool, roleLabel);
    final vncDefault = VncRemoteTarget.resolveValidVncHost(
      _codeController.text.trim(),
      prefix: 'PC',
    );
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: TextFormField(
        controller: c,
        enabled: !disabled,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) => tool == null
            ? null
            : RemoteParamValidator.validate(
                tool: tool,
                value: v ?? '',
                acceptsFileParam: acceptsFileParam,
              ),
        decoration: InputDecoration(
          labelText: labelText,
          border: const OutlineInputBorder(),
          prefixIcon: hasIcon
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: RemoteToolIcon(
                    iconAssetKey: tool!.iconAssetKey,
                    size: 20,
                    fallback: null,
                  ),
                )
              : null,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 24,
          ),
          helperText: historical
              ? 'Διατηρείται (αγνοείται όσο ισχύει «Μόνο ένα»)'
              : null,
          suffixIcon: historical
              ? Tooltip(
                  message: 'Ιστορική τιμή',
                  child: Icon(
                    Icons.history,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
          hintText: acceptsFileParam
              ? 'Αρχείο παραμέτρων πχ .rdp'
              : (isVnc ? (vncDefault ?? 'IP ή hostname') : null),
        ),
        keyboardType: isVnc
            ? const TextInputType.numberWithOptions(decimal: true, signed: false)
            : TextInputType.text,
        inputFormatters:
            isVnc ? [CommaToDotDecimalSeparatorFormatter()] : null,
        onChanged: (_) {
          _syncRemoteValueFromController(paramKey);
          setState(() {});
        },
      ),
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

  /// Προθέτει το όνομα εργαλείου στην ετικέτα όταν δεν εμφανίζεται ήδη
  /// (π.χ. «UltraVNC - Διεύθυνση…»). Το «Κωδικός AnyDesk» ήδη περιέχει AnyDesk.
  String _remoteParamLabelWithTool(RemoteTool? tool, String roleLabel) {
    if (tool == null) return roleLabel;
    final name = tool.name.trim();
    if (name.isEmpty) return roleLabel;
    final labelLower = roleLabel.toLowerCase();
    if (labelLower.contains(name.toLowerCase())) return roleLabel;
    if (tool.role == ToolRole.anydesk && labelLower.contains('anydesk')) {
      return roleLabel;
    }
    return '$name - $roleLabel';
  }
}
