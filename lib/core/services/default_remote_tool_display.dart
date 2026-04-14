import '../database/remote_tools_repository.dart';
import '../models/remote_tool.dart';

/// Εμφάνιση `equipment.default_remote_tool` (id ως TEXT) με ετικέτες ανενεργό / διαγραμμένο.
class DefaultRemoteToolDisplay {
  const DefaultRemoteToolDisplay({
    required this.label,
    required this.useMutedItalic,
  });

  final String label;
  final bool useMutedItalic;

  static DefaultRemoteToolDisplay resolve(
    String? stored,
    List<RemoteTool> allTools,
  ) {
    final raw = stored?.trim() ?? '';
    if (raw.isEmpty) {
      return const DefaultRemoteToolDisplay(label: '–', useMutedItalic: false);
    }
    final id = RemoteToolsRepository.parseDefaultRemoteToolId(stored);
    if (id == null) {
      return DefaultRemoteToolDisplay(label: raw, useMutedItalic: false);
    }
    RemoteTool? found;
    for (final t in allTools) {
      if (t.id == id) {
        found = t;
        break;
      }
    }
    if (found == null) {
      return DefaultRemoteToolDisplay(
        label: '(ανενεργό / διαγραμμένο) #$id',
        useMutedItalic: true,
      );
    }
    if (found.deletedAt != null) {
      return DefaultRemoteToolDisplay(
        label: '(ανενεργό / διαγραμμένο) ${found.name}',
        useMutedItalic: true,
      );
    }
    if (!found.isActive) {
      return DefaultRemoteToolDisplay(
        label: '(ανενεργό) ${found.name}',
        useMutedItalic: true,
      );
    }
    return DefaultRemoteToolDisplay(label: found.name, useMutedItalic: false);
  }
}
