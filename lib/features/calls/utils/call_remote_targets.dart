import '../../../core/database/remote_tools_repository.dart';
import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import '../models/equipment_model.dart';
import '../provider/smart_entity_selector_provider.dart';
import 'equipment_remote_param_key.dart';
import 'remote_target_rules.dart';
import 'vnc_remote_target.dart';

/// Επίλυση στόχων απομακρυσμένης σύνδεσης για τη φόρμα κλήσεων (με κατάλογο `remote_tools`).
abstract final class CallRemoteTargets {
  CallRemoteTargets._();

  static int _compareSortOrder(RemoteTool a, RemoteTool b) {
    final c = a.sortOrder.compareTo(b.sortOrder);
    if (c != 0) return c;
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    return a.id.compareTo(b.id);
  }

  static String? _equipmentNameForGeneric(SmartEntitySelectorState s) {
    if (s.selectedEquipment != null) {
      final code = s.selectedEquipment!.code?.trim() ?? '';
      if (code.isNotEmpty) return code;
    }
    final free = s.equipmentText.trim();
    return free.isEmpty ? null : free;
  }

  static bool _looksLikeRdpHost(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (VncRemoteTarget.tryParseIpv4Host(t) != null) return true;
    return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$').hasMatch(t) &&
        t.contains('.');
  }

  static String? resolvedAnyDeskTarget(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    if (s.selectedEquipment != null) {
      final fromDb = s.selectedEquipment!.anydeskIdResolved(tools)?.trim();
      if (fromDb == null || fromDb.isEmpty) return null;
      return RemoteTargetRules.isValidAnyDeskTarget(fromDb) ? fromDb : null;
    }
    return RemoteTargetRules.parseAnyDeskFromFreeText(s.equipmentText);
  }

  static bool canConnectAnyDesk(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) =>
      resolvedAnyDeskTarget(s, tools) != null;

  static String resolvedVncTarget(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    if (s.selectedEquipment != null) {
      return s.selectedEquipment!.vncTargetResolved(tools);
    }
    return VncRemoteTarget.hostForUnknownEquipmentText(s.equipmentText);
  }

  static bool canConnectVnc(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    if (s.selectedEquipment != null) {
      final raw = s.selectedEquipment!.vncTargetResolved(tools).trim();
      return raw.isNotEmpty && raw != 'Άγνωστο';
    }
    final free = VncRemoteTarget.hostForUnknownEquipmentText(s.equipmentText)
        .trim();
    return free.isNotEmpty && free != 'Άγνωστο';
  }

  static String? resolvedRdpHost(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    if (s.selectedEquipment != null) {
      final h = s.selectedEquipment!.rdpHostResolved(tools)?.trim();
      if (h != null && h.isNotEmpty) {
        if (_looksLikeRdpHost(h)) return h;
        return null;
      }
    }
    final t = s.equipmentText.trim();
    if (t.isEmpty) return null;
    final ip = VncRemoteTarget.tryParseIpv4Host(t);
    if (ip != null) return ip;
    if (_looksLikeRdpHost(t)) return t;
    return null;
  }

  static bool canConnectRdp(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) =>
      resolvedRdpHost(s, tools) != null;

  /// Στόχος εκκίνησης ανά ορισμό εργαλείου (`ToolRole`).
  static String? resolvedLaunchTarget(
    SmartEntitySelectorState s,
    RemoteTool tool,
    List<RemoteTool> tools,
  ) {
    switch (tool.role) {
      case ToolRole.anydesk:
        return resolvedAnyDeskTarget(s, tools);
      case ToolRole.rdp:
        return resolvedRdpHost(s, tools);
      case ToolRole.vnc:
        RemoteTool? vncDef;
        for (final t in tools) {
          if (t.role == ToolRole.vnc) {
            vncDef = t;
            break;
          }
        }
        final useTool =
            vncDef != null && tool.id == vncDef.id ? vncDef : tool;
        if (s.selectedEquipment != null) {
          final h = s.selectedEquipment!.vncLikeTargetResolved(useTool).trim();
          if (h.isEmpty || h == 'Άγνωστο') return null;
          return h;
        }
        final free = VncRemoteTarget.hostForUnknownEquipmentText(s.equipmentText)
            .trim();
        if (free.isEmpty || free == 'Άγνωστο') return null;
        return free;
      case ToolRole.generic:
        return _equipmentNameForGeneric(s);
    }
  }

  static bool canConnectForTool(
    SmartEntitySelectorState s,
    RemoteTool tool,
    List<RemoteTool> tools,
  ) =>
      resolvedLaunchTarget(s, tool, tools) != null;

  static String targetSubtitle(
    SmartEntitySelectorState s,
    RemoteTool tool,
    List<RemoteTool> tools,
  ) {
    switch (tool.role) {
      case ToolRole.anydesk:
        return anydeskTargetDisplay(s, tools);
      case ToolRole.rdp:
        return resolvedRdpHost(s, tools) ?? '—';
      case ToolRole.vnc:
        return resolvedVncTarget(s, tools);
      case ToolRole.generic:
        return '—';
    }
  }

  static String anydeskTargetDisplay(
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    final r = resolvedAnyDeskTarget(s, tools);
    if (r != null) return r;
    final fromEq = s.selectedEquipment?.anydeskIdResolved(tools)?.trim();
    if (fromEq != null && fromEq.isNotEmpty) return fromEq;
    return '—';
  }

  /// Μη επιλεγμένο εργαλείο: `remote_params` έχει τιμή για το id εργαλείου ή legacy κλειδί ρόλου / στήλες.
  static bool _equipmentHasNonDefaultParamForTool(
    RemoteTool tool,
    EquipmentModel eq,
  ) {
    final p = eq.remoteParams;
    final idKey = tool.id.toString();
    if ((p[idKey]?.trim().isNotEmpty ?? false)) return true;
    switch (tool.role) {
      case ToolRole.anydesk:
        if ((p[EquipmentRemoteParamKey.anydesk]?.trim().isNotEmpty ?? false)) {
          return true;
        }
        return eq.anydeskId?.trim().isNotEmpty ?? false;
      case ToolRole.vnc:
        if ((p[EquipmentRemoteParamKey.vnc]?.trim().isNotEmpty ?? false)) {
          return true;
        }
        return eq.customIp?.trim().isNotEmpty ?? false;
      case ToolRole.rdp:
        if ((p[EquipmentRemoteParamKey.rdp]?.trim().isNotEmpty ?? false)) {
          return true;
        }
        return false;
      case ToolRole.generic:
        return false;
    }
  }

  /// Ελεύθερο κείμενο εξοπλισμού (χωρίς εγγραφή καταλόγου): εργαλείο «ταιριάζει» αν ο ρόλος
  /// συνδέεται με εξαγγελμένο στόχο από το κείμενο.
  static bool toolMatchesFreeEquipmentText(
    RemoteTool tool,
    SmartEntitySelectorState s,
    List<RemoteTool> tools,
  ) {
    switch (tool.role) {
      case ToolRole.anydesk:
        return RemoteTargetRules.parseAnyDeskFromFreeText(s.equipmentText) !=
            null;
      case ToolRole.vnc:
        final h =
            VncRemoteTarget.hostForUnknownEquipmentText(s.equipmentText).trim();
        return h.isNotEmpty && h != 'Άγνωστο';
      case ToolRole.rdp:
        return resolvedRdpHost(s, tools) != null;
      case ToolRole.generic:
        return s.equipmentText.trim().isNotEmpty;
    }
  }

  /// Εργαλεία που εμφανίζονται στη γραμμή κλήσης (ο κατάλογος είναι ήδη ενεργά `remote_tools`).
  ///
  /// Με εξοπλισμό από βάση: πάντα το προεπιλεγμένο εργαλείο + όσα έχουν παράμετρο με τιμή.
  /// Με ελεύθερο κείμενο: όσα ενεργά εργαλεία [toolMatchesFreeEquipmentText] επιστρέφει true.
  static List<RemoteTool> visibleRemoteToolsForCallState(
    SmartEntitySelectorState s,
    List<RemoteTool> catalog,
  ) {
    if (catalog.isEmpty) return [];
    final candidates = <RemoteTool>[];
    if (s.selectedEquipment != null) {
      final eq = s.selectedEquipment!;
      final defId =
          RemoteToolsRepository.parseDefaultRemoteToolId(eq.defaultRemoteTool);
      for (final t in catalog) {
        if (defId != null && t.id == defId) {
          candidates.add(t);
          continue;
        }
        if (t.role == ToolRole.vnc && canConnectForTool(s, t, catalog)) {
          candidates.add(t);
          continue;
        }
        if (_equipmentHasNonDefaultParamForTool(t, eq)) {
          candidates.add(t);
        }
      }
    } else {
      final text = s.equipmentText.trim();
      if (text.isEmpty) return [];
      for (final t in catalog) {
        if (toolMatchesFreeEquipmentText(t, s, catalog)) {
          candidates.add(t);
        }
      }
    }

    // Stage A: strict validation (μόνο εργαλεία με έγκυρο στόχο).
    final validTools = <RemoteTool>[];
    for (final t in candidates) {
      if (canConnectForTool(s, t, catalog)) {
        validTools.add(t);
      }
    }
    if (validTools.isEmpty) return [];

    // Stage B: suppression (αν υπάρχει αποκλειστικό, κρατάμε μόνο αποκλειστικά).
    final hasExclusive = validTools.any((t) => t.isExclusive);
    final finalTools = hasExclusive
        ? validTools.where((t) => t.isExclusive).toList()
        : validTools;

    // Stage C: sorting (sort_order, name, id).
    finalTools.sort(_compareSortOrder);
    return finalTools;
  }

  /// Κρύβει πλήρως τα κουμπιά σύνδεσης όταν το προεπιλεγμένο εργαλείο (id) είναι ανενεργό / διαγραμμένο / ορφανό.
  static bool shouldHideRemoteConnectionButtons(
    EquipmentModel? equipment,
    List<RemoteTool> allToolsCatalog,
  ) {
    if (equipment == null) return false;
    final id = RemoteToolsRepository.parseDefaultRemoteToolId(
      equipment.defaultRemoteTool,
    );
    if (id == null) return false;
    RemoteTool? found;
    for (final t in allToolsCatalog) {
      if (t.id == id) {
        found = t;
        break;
      }
    }
    if (found == null) return true;
    if (!found.isActive || found.deletedAt != null) return true;
    return false;
  }
}
