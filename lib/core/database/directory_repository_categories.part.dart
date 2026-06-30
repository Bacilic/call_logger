part of 'directory_repository.dart';

mixin DirectoryRepositoryCategories on DirectoryRepositoryBase {
  Future<List<String>> getCategoryNames() => _categories.getCategoryNames();

  Future<List<Map<String, dynamic>>> getActiveCategoryRows() =>
      _categories.getActiveCategoryRows();

  Future<({int id, String name})?> findActiveCategoryByNormalizedName(
    String input,
  ) =>
      _categories.findActiveCategoryByNormalizedName(input);

  Future<bool> categoryNormalizedNameTaken(
    String name, {
    int? excludeId,
  }) =>
      _categories.categoryNormalizedNameTaken(name, excludeId: excludeId);

  Future<({int id, bool restored})> insertCategoryAndGetId(
    String name, {
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) =>
      _categories.insertCategoryAndGetId(
        name,
        rebuildSearchIndexInTxn: rebuildSearchIndexInTxn,
      );

  Future<void> updateCategoryNameAndSyncCalls({
    required int id,
    required String newCanonicalName,
    required RebuildCallSearchIndexForCategoryInTxn rebuildSearchIndexInTxn,
  }) =>
      _categories.updateCategoryNameAndSyncCalls(
        id: id,
        newCanonicalName: newCanonicalName,
        rebuildSearchIndexInTxn: rebuildSearchIndexInTxn,
      );

  Future<void> softDeleteCategories(List<int> ids) =>
      _categories.softDeleteCategories(ids);

  Future<void> restoreCategories(List<int> ids) =>
      _categories.restoreCategories(ids);
}
