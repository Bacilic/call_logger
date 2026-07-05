import '../../../../core/database/remote_tools_repository.dart';
import '../../../../core/models/remote_tool.dart';

/// Λογική αποθήκευσης φόρμας εργαλείου (χωρίς UI).
class RemoteToolFormSaver {
  RemoteToolFormSaver(this._repo);

  final RemoteToolsRepository _repo;

  Future<List<RemoteTool>> loadNonDeleted() => _repo.getAllNonDeletedTools();

  Future<RemoteTool?> findSoftDeletedConflict(
    String name, {
    int? excludeId,
  }) =>
      _repo.findFirstSoftDeletedByNameInsensitive(
        name,
        excludeToolId: excludeId,
      );

  Future<void> disambiguateSoftDeleted(int id) =>
      _repo.disambiguateSoftDeletedToolName(id);

  Future<int> commitNew({
    required RemoteTool toolFromForm,
  }) async {
    final fresh = await _repo.getAllNonDeletedTools();
    final n = fresh.length;
    final toInsert = toolFromForm.copyWith(sortOrder: n + 1);
    final newId = await _repo.insertTool(toInsert);
    await _repo.reorderToolToPosition(
      toolId: newId,
      positionOneBased: n + 1,
    );
    return newId;
  }

  Future<void> commitEdit({
    required RemoteTool toolFromForm,
  }) async {
    final fresh = await _repo.getAllNonDeletedTools();
    final id = toolFromForm.id;
    var currentSort = toolFromForm.sortOrder;
    for (final t in fresh) {
      if (t.id == id) {
        currentSort = t.sortOrder;
        break;
      }
    }
    final updated = toolFromForm.copyWith(sortOrder: currentSort);
    await _repo.updateTool(updated);
  }

  Future<void> commitRestoreSoftDeleted({
    required RemoteTool toolFromForm,
    int? editCurrentIdToDelete,
  }) async {
    final allNonDeleted = await _repo.getAllNonDeletedTools();
    final n = allNonDeleted.length;
    final restored = toolFromForm.copyWith(sortOrder: n + 1);
    await _repo.restoreToolClearDeleted(restored);
    if (editCurrentIdToDelete != null &&
        editCurrentIdToDelete != toolFromForm.id) {
      await _repo.deleteTool(editCurrentIdToDelete);
    }
    await _repo.reorderToolToPosition(
      toolId: toolFromForm.id,
      positionOneBased: n + 1,
    );
  }
}
