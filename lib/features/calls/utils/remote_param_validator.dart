import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';
import 'remote_target_rules.dart';
import 'vnc_remote_target.dart';

/// Επικύρωση τιμής παραμέτρου απομακρυσμένου εργαλείου στη φόρμα εξοπλισμού.
abstract final class RemoteParamValidator {
  RemoteParamValidator._();

  static const _invalidAnyDeskMessage =
      'Μη έγκυρος κωδικός AnyDesk — 9–10 ψηφία ή name@namespace.';
  static const _invalidRdpFileMessage = 'Δώστε διαδρομή αρχείου .rdp.';
  static const _invalidHostMessage =
      'Μη έγκυρη διεύθυνση — δώστε IP ή όνομα υπολογιστή.';

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
        return VncRemoteTarget.resolveValidVncHost(value) != null
            ? null
            : _invalidHostMessage;
      case ToolRole.vnc:
        return VncRemoteTarget.resolveValidVncHost(value) != null
            ? null
            : _invalidHostMessage;
      case ToolRole.generic:
        return null;
    }
  }
}
