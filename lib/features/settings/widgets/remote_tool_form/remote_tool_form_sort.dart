import '../../../../core/models/remote_tool.dart';

/// Ταξινόμηση όπως στο [RemoteToolsRepository] (sort_order, name, id).
List<RemoteTool> sortedRemoteTools(List<RemoteTool> tools) {
  final s = [...tools]..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        final n = a.name.compareTo(b.name);
        if (n != 0) return n;
        return a.id.compareTo(b.id);
      });
  return s;
}
