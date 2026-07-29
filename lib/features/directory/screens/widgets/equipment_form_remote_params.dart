import 'package:flutter/material.dart';

import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';
import '../../../../core/widgets/info_hint_icon.dart';
import '../../../../core/widgets/remote_tool_icon.dart';
import '../../../calls/models/equipment_model.dart';
import '../../../calls/provider/remote_paths_provider.dart';
import '../../../calls/utils/equipment_remote_param_key.dart';
import '../../../calls/utils/remote_param_validator.dart';
import '../../../calls/utils/vnc_remote_target.dart';
import 'equipment_form_dialog.dart';
import 'remote_param_help_text.dart';

/// Παράμετροι απομακρυσμένης σύνδεσης της φόρμας εξοπλισμού: αρχικοποίηση από
/// `remote_params`, εκκαθάριση άγνωστων κλειδιών, Ζώνες Α/Β του UI.
///
/// Συνεργάτης του [EquipmentFormDialogState] (Σύνθεση).
class EquipmentFormRemoteParams {
  EquipmentFormRemoteParams(this.host);

  final EquipmentFormDialogState host;

  void initFromEquipment(EquipmentModel? e) {
    host.remoteParamValues.clear();
    host.expandedRemoteKeys.clear();
    host.exclusiveRemoteToolId = null;
    if (e == null) return;
    host.exclusiveRemoteToolId = EquipmentRemoteParamKey.exclusiveToolIdFrom(
      e.remoteParams,
    );
    // Φόρτωσε όλες τις τιμές (και τις ιστορικές `__stash_`) κάτω από το πραγματικό
    // κλειδί `<tool_id>`· οι ενεργές τιμές υπερισχύουν των ιστορικών.
    for (final entry in e.remoteParams.entries) {
      if (entry.key == EquipmentRemoteParamKey.exclusiveToolKey) continue;
      final stashReal = EquipmentRemoteParamKey.remoteParamStashRealKeyOrNull(
        entry.key,
      );
      final realKey = stashReal ?? entry.key;
      if (int.tryParse(realKey) == null) continue;
      if (stashReal != null && host.remoteParamValues.containsKey(realKey)) {
        continue;
      }
      host.remoteParamValues[realKey] = entry.value;
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

  bool isHostAddressParamKey(
    String key,
    List<RemoteTool> catalog,
    List<RemoteToolFormPair> pairs,
  ) {
    final tool = _toolForParamKey(key, catalog);
    if (tool == null) return false;
    if (tool.role == ToolRole.vnc) return true;
    if (tool.role == ToolRole.rdp && !_toolAcceptsFileParam(key, pairs)) {
      return true;
    }
    return false;
  }

  Future<void> pruneAfterCatalogLoad() async {
    if (!host.mounted || host.didPruneUnknownRemoteKeys) return;
    final pairs = await host.widget.ref.read(remoteToolFormPairsProvider.future);
    if (!host.mounted || host.didPruneUnknownRemoteKeys) return;
    host.didPruneUnknownRemoteKeys = true;
    _syncRemoteParamsToForm(pairs);
    host.dismissGuard.tryCaptureFormBaseline();
    host.markFormChanged();
  }

  /// Κάθε εργαλείο της φόρμας έχει πεδίο (κλειδί = `<tool_id>`). Καθαρίζει τιμές
  /// που δεν αντιστοιχούν σε εργαλείο της φόρμας και ακυρώνει άκυρο αποκλειστικό.
  void _syncRemoteParamsToForm(List<RemoteToolFormPair> pairs) {
    final formKeys = {for (final p in pairs) p.key};
    for (final k in host.remoteParamValues.keys.toList()) {
      if (!formKeys.contains(k)) {
        host.remoteParamValues.remove(k);
        _disposeRemoteController(k);
      }
    }
    host.expandedRemoteKeys
      ..clear()
      ..addAll(formKeys);
    for (final k in host.expandedRemoteKeys) {
      _ensureRemoteController(k);
    }
    if (host.exclusiveRemoteToolId != null &&
        !formKeys.contains('${host.exclusiveRemoteToolId}')) {
      host.exclusiveRemoteToolId = null;
    }
  }

  void _ensureRemoteController(String key) {
    if (host.remoteParamControllers.containsKey(key)) return;
    host.remoteParamControllers[key] = TextEditingController(
      text: host.remoteParamValues[key] ?? '',
    );
  }

  void _disposeRemoteController(String key) {
    final c = host.remoteParamControllers.remove(key);
    c?.dispose();
  }

  void syncValueFromController(String key) {
    final c = host.remoteParamControllers[key];
    if (c == null) return;
    final t = c.text.trim();
    if (t.isEmpty) {
      host.remoteParamValues.remove(key);
    } else {
      host.remoteParamValues[key] = c.text;
    }
  }

  Widget buildSection(List<RemoteToolFormPair> pairs, List<RemoteTool> catalog) {
    final theme = Theme.of(host.context);
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
    // πριν ολοκληρωθεί το async prune (που συγχρονίζει το `expandedRemoteKeys`).
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

    final exclusiveValid =
        host.exclusiveRemoteToolId != null &&
        toolForId(host.exclusiveRemoteToolId!) != null;
    final int? zoneAValue = exclusiveValid ? host.exclusiveRemoteToolId : null;

    // Ζώνη Α — προειδοποίηση όταν το «μόνο» εργαλείο χρειάζεται παράμετρο και είναι κενή.
    String? warning;
    if (zoneAValue != null) {
      final selTool = toolForId(zoneAValue);
      final selParam = (host.remoteParamControllers['$zoneAValue']?.text ?? '')
          .trim();
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
        final hasValue = (host.remoteParamValues[key] ?? '').trim().isNotEmpty;
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
        rows.add(_buildRemoteParamField(key, pairs, catalog));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Εμφάνιση στην κλήση: Επιλέξτε «Όλα» ή ένα μόνο εργαλείο για αυτόν τον εξοπλισμό.',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          key: ValueKey('zoneA-${zoneAValue ?? 'all'}'),
          initialValue: zoneAValue,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
            host.exclusiveRemoteToolId = v;
            host.markFormChanged();
            host.dismissGuard.tryCaptureFormBaseline();
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
    final c = host.remoteParamControllers[paramKey];
    if (c == null) return const SizedBox.shrink();
    final theme = Theme.of(host.context);
    final isHostAddress = isHostAddressParamKey(paramKey, catalog, pairs);
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
    final helpText = RemoteParamHelpText.forTool(
      tool: tool,
      acceptsFileParam: acceptsFileParam,
    );
    final vncDefault = VncRemoteTarget.resolveValidVncHost(
      host.codeController.text.trim(),
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
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (historical)
                Tooltip(
                  message: 'Ιστορική τιμή',
                  child: Icon(
                    Icons.history,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InfoHintIcon(message: helpText),
              ),
            ],
          ),
          hintText: acceptsFileParam
              ? 'Αρχείο παραμέτρων πχ .rdp'
              : (isHostAddress ? (vncDefault ?? 'IP ή hostname') : null),
        ),
        keyboardType: isHostAddress
            ? const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              )
            : TextInputType.text,
        inputFormatters: isHostAddress
            ? [CommaToDotDecimalSeparatorFormatter()]
            : null,
        onChanged: (_) {
          syncValueFromController(paramKey);
          host.markFormChanged();
        },
      ),
    );
  }

  bool _toolAcceptsFileParam(String key, List<RemoteToolFormPair> pairs) {
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
