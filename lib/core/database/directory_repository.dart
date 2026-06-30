import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/building_map_floor.dart';
import 'user_delete_phone_policy.dart';
import 'category_repository.dart';
import 'building_map_repository.dart';
import 'department_repository.dart';
import 'equipment_repository.dart';
import 'phone_repository.dart';
import 'user_repository.dart';
import 'directory_support.dart';
import 'omnisearch_service.dart';
import 'integrity_service.dart';

export 'category_repository.dart' show RebuildCallSearchIndexForCategoryInTxn;
export 'department_repository.dart' show DepartmentNameKeyBackfillResult;
export 'omnisearch_service.dart'
    show BuildingMapOmnisearchHit, BuildingMapOmnisearchEntityKind;

part 'directory_repository_phones.part.dart';
part 'directory_repository_users.part.dart';
part 'directory_repository_departments.part.dart';
part 'directory_repository_equipment.part.dart';
part 'directory_repository_categories.part.dart';
part 'directory_repository_building_map.part.dart';
part 'directory_repository_settings_search.part.dart';
part 'directory_repository_integrity.part.dart';

/// Persistence καταλόγου: χρήστες, τμήματα, εξοπλισμός, κατηγορίες, ρυθμίσεις, εισαγωγές.
///
/// Δεν εισάγει [CallsRepository] — το rebuild `search_index` γίνεται μέσω [RebuildCallSearchIndexForCategoryInTxn].
class DirectoryRepositoryBase {
  DirectoryRepositoryBase(this.db);

  final Database db;
  late final DirectorySupport _support = DirectorySupport(db);
  late final CategoryRepository _categories =
      CategoryRepository(db, support: _support);
  late final BuildingMapRepository _buildingMap =
      BuildingMapRepository(db, _support);
  late final DepartmentRepository _departments =
      DepartmentRepository(db, support: _support);
  late final EquipmentRepository _equipment =
      EquipmentRepository(db, support: _support);
  late final PhoneRepository _phones = PhoneRepository(db, support: _support);
  late final UserRepository _users =
      UserRepository(db, support: _support, departments: _departments);
  late final IntegrityService _integrity =
      IntegrityService(db, _support, _users);
  late final OmnisearchService _omnisearch = OmnisearchService(db, _support);
}

class DirectoryRepository extends DirectoryRepositoryBase
    with
        DirectoryRepositoryPhones,
        DirectoryRepositoryUsers,
        DirectoryRepositoryDepartments,
        DirectoryRepositoryEquipment,
        DirectoryRepositoryCategories,
        DirectoryRepositoryBuildingMap,
        DirectoryRepositorySettingsSearch,
        DirectoryRepositoryIntegrity {
  DirectoryRepository(super.db) {
    _buildingMap.bindUpdateDepartment(
      (deptId, fields) async {
        await _departments.updateDepartment(deptId, fields);
      },
    );
  }

  /// Πυρήνας «τοποθέτησης χάρτη» — προώθηση στο [BuildingMapRepository].
  static Map<String, dynamic> clearedBuildingMapPlacementColumns({
    bool clearFloorId = false,
    bool clearDepartmentHex = false,
  }) =>
      BuildingMapRepository.clearedBuildingMapPlacementColumns(
        clearFloorId: clearFloorId,
        clearDepartmentHex: clearDepartmentHex,
      );

  /// Ονόματα στηλών που επηρεάζονται από [clearedBuildingMapPlacementColumns].
  static Iterable<String> get buildingMapPlacementColumnNames =>
      BuildingMapRepository.buildingMapPlacementColumnNames;
}
