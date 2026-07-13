import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import 'remote_target_rules.dart';
import 'vnc_remote_target.dart';

/// Επικύρωση τιμής παραμέτρου απομακρυμένου εργαλείου στη φόρμα εξοπλισμού.
abstract final class RemoteParamValidator {
  RemoteParamValidator._();

  static const _invalidAnyDeskMessage =
      'Μη έγκυρος κωδικός AnyDesk — 9–10 ψηφία ή name@namespace.';
  static const _invalidRdpFileMessage = 'Δώστε διαδρομή αρχείου .rdp.';
  static const _invalidHostMessage =
      'Μη έγκυρη διεύθυνση — δώστε IP ή όνομα υπολογιστή.';

  static final RegExp _plainEquipmentCode = RegExp(r'^\d{3,6}$');

  /// Κενή τιμή (μετά trim) → null (έγκυρο, προαιρετικό πεδίο).
  static String? validate({
    required RemoteTool tool,
    required String value,
    required bool acceptsFileParam,
  }) {
    if (value.trim().isEmpty) return null;

    switch (tool.role) {
      case ToolRole.anydesk:
        return RemoteTargetRules.isValidAnyDeskTarget(value)
            ? null
            : _invalidAnyDeskMessage;
      case ToolRole.rdp:
        if (acceptsFileParam) {
          return value.trim().toLowerCase().endsWith('.rdp')
              ? null
              : _invalidRdpFileMessage;
        }
        return _validateHostAddress(value);
      case ToolRole.vnc:
        return _validateHostAddress(value);
      case ToolRole.generic:
        return null;
    }
  }

  /// Επικύρωση host (VNC/RDP χωρίς αρχείο) — κοινή για φόρμα εξοπλισμού και πίνακα δοκιμής.
  static String? validateHostAddress(String value) => _validateHostAddress(value);

  static String? _validateHostAddress(String value) {
    if (VncRemoteTarget.resolveValidVncHost(value) != null) return null;
    return diagnoseIpAttempt(value) ?? _invalidHostMessage;
  }

  /// Στοχευμένη διάγνωση όταν το κείμενο μοιάζει με απόπειρα IPv4 (όχι σκέτος κωδικός 3–6 ψηφίων).
  static String? diagnoseIpAttempt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll(',', '.');
    if (!RegExp(r'^\d').hasMatch(normalized)) return null;
    if (!normalized.contains('.')) return null;
    if (_plainEquipmentCode.hasMatch(normalized)) return null;

    if (RegExp(r'\s').hasMatch(trimmed)) {
      return 'Η διεύθυνση περιέχει κενό — αφαιρέστε το.';
    }

    if (normalized.startsWith('.') ||
        normalized.endsWith('.') ||
        normalized.contains('..')) {
      return 'Διπλή ή τελική τελεία στη διεύθυνση.';
    }

    final groups = normalized.split('.');
    if (groups.any((g) => g.isEmpty)) {
      return 'Διπλή ή τελική τελεία στη διεύθυνση.';
    }

    for (final group in groups) {
      for (final rune in group.runes) {
        final ch = String.fromCharCode(rune);
        if (RegExp(r'^\d$').hasMatch(ch)) continue;
        if (ch == 'O' || ch == 'o' || ch == 'Ο' || ch == 'ο') {
          return 'Περιέχει το γράμμα "Ο" αντί για τον αριθμό 0.';
        }
        return 'Μη αποδεκτός χαρακτήρας "$ch" στη διεύθυνση.';
      }
    }

    if (groups.length != 4) {
      return 'Η IP θέλει 4 αριθμούς χωρισμένους με τελείες — βρέθηκαν ${groups.length}.';
    }

    for (final group in groups) {
      final n = int.tryParse(group);
      if (n != null && n > 255) {
        return 'Το $n ξεπερνά το όριο 255 κάθε τμήματος της IP.';
      }
    }

    return null;
  }
}
