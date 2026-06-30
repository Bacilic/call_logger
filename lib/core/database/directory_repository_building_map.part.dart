part of 'directory_repository.dart';

mixin DirectoryRepositoryBuildingMap on DirectoryRepositoryBase {
  Future<List<BuildingMapFloor>> listBuildingMapFloors() =>
      _buildingMap.listBuildingMapFloors();

  Future<int> insertBuildingMapFloor({
    required String label,
    String? floorGroup,
    required String copiedImagePath,
    required double rotationDegrees,
  }) =>
      _buildingMap.insertBuildingMapFloor(
        label: label,
        floorGroup: floorGroup,
        copiedImagePath: copiedImagePath,
        rotationDegrees: rotationDegrees,
      );

  Future<void> updateBuildingMapFloor(
    int id, {
    double? rotationDegrees,
    String? label,
    String? floorGroup,
    String? imagePath,
  }) =>
      _buildingMap.updateBuildingMapFloor(
        id,
        rotationDegrees: rotationDegrees,
        label: label,
        floorGroup: floorGroup,
        imagePath: imagePath,
      );

  Future<int> countDepartmentsReferencingMapFloor(int floorId) =>
      _buildingMap.countDepartmentsReferencingMapFloor(floorId);

  Future<void> deleteBuildingMapFloorClearingDepartmentMaps(int id) =>
      _buildingMap.deleteBuildingMapFloorClearingDepartmentMaps(id);
}
