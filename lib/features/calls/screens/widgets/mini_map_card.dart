import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../directory/building_map/screens/building_map_dialog.dart';
import '../../../directory/models/department_model.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';

enum _MiniMapMode { equipment, phone, user }

class MiniMapCard extends ConsumerStatefulWidget {
  const MiniMapCard({
    super.key,
    required this.equipment,
    required this.equipmentCodeText,
    required this.phoneText,
    required this.user,
  });

  final EquipmentModel? equipment;
  final String equipmentCodeText;
  final String phoneText;
  final UserModel? user;

  @override
  ConsumerState<MiniMapCard> createState() => _MiniMapCardState();
}

class _MiniMapCardState extends ConsumerState<MiniMapCard> {
  static const double _kCardWidth = 336;
  static const double _kSnapshotHeight = 170;

  late Future<_MiniMapCardData> _dataFuture;
  _MiniMapMode _mode = _MiniMapMode.equipment;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void didUpdateWidget(covariant MiniMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.equipment?.id != widget.equipment?.id ||
        oldWidget.equipment?.departmentId != widget.equipment?.departmentId ||
        oldWidget.equipmentCodeText != widget.equipmentCodeText ||
        oldWidget.phoneText != widget.phoneText ||
        oldWidget.user?.id != widget.user?.id ||
        oldWidget.user?.departmentId != widget.user?.departmentId;
    if (changed) {
      _dataFuture = _loadData();
    }
  }

  Future<List<int>> _departmentIdsForUserId(
    Database db,
    int userId,
  ) async {
    final rows = await db.rawQuery(
      '''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
      SELECT DISTINCT src.department_id AS department_id
      FROM (
        SELECT u.department_id AS department_id
        FROM users u
        WHERE u.id = ? AND u.department_id IS NOT NULL
        UNION
        SELECT pd.department_id AS department_id
        FROM user_phones up
        JOIN phone_dept pd ON pd.phone_id = up.phone_id
        WHERE up.user_id = ?
      ) src
      JOIN departments d ON d.id = src.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
      ORDER BY src.department_id ASC
      ''',
      [userId, userId],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<List<int>> _departmentIdsForPhone(Database db, String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''
      WITH phone_dept AS (
        SELECT p.id AS phone_id, p.department_id AS department_id
        FROM phones p
        WHERE p.department_id IS NOT NULL
        UNION
        SELECT dp.phone_id AS phone_id, dp.department_id AS department_id
        FROM department_phones dp
      )
      SELECT DISTINCT pd.department_id AS department_id
      FROM phones p
      JOIN phone_dept pd ON pd.phone_id = p.id
      JOIN departments d ON d.id = pd.department_id
      WHERE COALESCE(d.is_deleted, 0) = 0
        AND p.number = ?
      ORDER BY pd.department_id ASC
      ''',
      [trimmed],
    );
    return rows
        .map((row) => row['department_id'] as int?)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<List<int>> _departmentIdsForEquipment(
    Database db,
    EquipmentModel equipment,
  ) async {
    final direct = equipment.departmentId;
    if (direct != null) return [direct];
    final equipmentId = equipment.id;
    if (equipmentId == null) return const [];
    final linkedUsers = await db.rawQuery(
      '''
      SELECT user_id
      FROM user_equipment
      WHERE equipment_id = ?
      ORDER BY user_id ASC
      ''',
      [equipmentId],
    );
    final ids = <int>{};
    for (final row in linkedUsers) {
      final uid = row['user_id'] as int?;
      if (uid == null) continue;
      ids.addAll(await _departmentIdsForUserId(db, uid));
    }
    return ids.toList()..sort();
  }

  Future<EquipmentModel?> _resolveEquipment(Database db) async {
    if (widget.equipment != null) return widget.equipment;
    final query = widget.equipmentCodeText.trim();
    if (query.isEmpty) return null;
    final lookup = LookupService.instance;
    await lookup.loadFromDatabase();
    final found = lookup.findEquipmentsByCode(query);
    if (found.length == 1) return found.first;
    return null;
  }

  Future<_MiniMapCardData> _loadData() async {
    final db = await DatabaseHelper.instance.database;
    final repo = DirectoryRepository(db);
    final floors = await repo.listBuildingMapFloors();
    final departmentRows = await repo.getDepartments();
    final departments = departmentRows
        .map(DepartmentModel.fromMap)
        .where((d) => !d.isDeleted)
        .toList(growable: false);
    final byId = <int, DepartmentModel>{
      for (final d in departments)
        if (d.id != null) d.id!: d,
    };

    final equipment = await _resolveEquipment(db);
    final equipmentDeptIds = equipment == null
        ? const <int>[]
        : await _departmentIdsForEquipment(db, equipment);
    final phoneDeptIds = await _departmentIdsForPhone(db, widget.phoneText);

    final userDeptId = widget.user?.departmentId;
    final userDeptIds = userDeptId == null ? const <int>[] : <int>[userDeptId];

    final equipmentDeptId = equipmentDeptIds.isNotEmpty ? equipmentDeptIds.first : null;
    final phoneDeptId = phoneDeptIds.isNotEmpty ? phoneDeptIds.first : null;
    final userDeptFallback = userDeptIds.isNotEmpty ? userDeptIds.first : null;

    _MiniMapMode mode = _MiniMapMode.equipment;
    if (equipmentDeptId == null && phoneDeptId != null) {
      mode = _MiniMapMode.phone;
    } else if (equipmentDeptId == null &&
        phoneDeptId == null &&
        userDeptFallback != null) {
      mode = _MiniMapMode.user;
    }

    final hasToggle =
        equipmentDeptId != null &&
        phoneDeptId != null &&
        equipmentDeptId != phoneDeptId;
    final selectedDeptId = switch (mode) {
      _MiniMapMode.equipment => equipmentDeptId ?? phoneDeptId ?? userDeptFallback,
      _MiniMapMode.phone => phoneDeptId ?? equipmentDeptId ?? userDeptFallback,
      _MiniMapMode.user => userDeptFallback ?? equipmentDeptId ?? phoneDeptId,
    };

    return _MiniMapCardData(
      floors: floors,
      departmentsById: byId,
      selectedDepartmentId: selectedDeptId,
      hasPhoneEquipmentToggle: hasToggle,
      initialMode: mode,
      equipmentEntity: equipment,
      equipmentDepartmentId: equipmentDeptId,
      phoneDepartmentId: phoneDeptId,
      userDepartmentId: userDeptFallback,
    );
  }

  _MiniMapTarget _targetForMode(
    _MiniMapCardData data,
    _MiniMapMode mode,
  ) {
    final fallback = data.selectedDepartmentId;
    if (mode == _MiniMapMode.phone) {
      return _MiniMapTarget(
        label: 'Θέση τηλεφώνου',
        departmentId: data.phoneDepartmentId ?? fallback,
        pendingEntity: widget.phoneText.trim().isEmpty ? null : widget.phoneText.trim(),
      );
    }
    if (mode == _MiniMapMode.user) {
      return _MiniMapTarget(
        label: 'Θέση υπαλλήλου',
        departmentId: data.userDepartmentId ?? fallback,
        pendingEntity: widget.user,
      );
    }
    return _MiniMapTarget(
      label: 'Θέση εξοπλισμού',
      departmentId: data.equipmentDepartmentId ?? fallback,
      pendingEntity: data.equipmentEntity,
    );
  }

  Widget _buildSnapshot(
    BuildContext context,
    _MiniMapTarget target,
    _MiniMapCardData data,
  ) {
    final deptId = target.departmentId;
    final dept = deptId == null ? null : data.departmentsById[deptId];
    if (dept == null) {
      return _placeholder(context, 'Δεν βρέθηκε τμήμα για προεπισκόπηση.');
    }
    final floorId = dept.mapFloor == null ? null : int.tryParse(dept.mapFloor!.trim());
    final floor = floorId == null
        ? data.floors.firstOrNull
        : data.floors.cast<BuildingMapFloor?>().firstWhere(
              (f) => f?.id == floorId,
              orElse: () => data.floors.firstOrNull,
            );
    if (floor == null) {
      return _placeholder(context, 'Δεν υπάρχει διαθέσιμο φύλλο χάρτη.');
    }
    final imagePath = floor.imagePath.trim();
    final imageExists = imagePath.isNotEmpty && File(imagePath).existsSync();
    if (!imageExists) {
      return _placeholder(context, 'Δεν βρέθηκε αρχείο κατόψης.');
    }

    final nx = dept.mapX;
    final ny = dept.mapY;
    final nw = dept.mapWidth;
    final nh = dept.mapHeight;
    final mapped =
        nx != null && ny != null && nw != null && nh != null && nw > 0 && nh > 0;
    if (!mapped) {
      return ClipRect(
        child: Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            width: _kCardWidth,
            height: _kSnapshotHeight,
            filterQuality: FilterQuality.medium,
          ),
        ),
      );
    }

    final cx = (nx + (nw / 2)).clamp(0.0, 1.0);
    final cy = (ny + (nh / 2)).clamp(0.0, 1.0);
    final span = nw > nh ? nw : nh;
    // Δείχνουμε περισσότερο περιβάλλον για να μη φαίνεται «κενή περιοχή».
    // Στόχος: το μεγαλύτερο dimension του τμήματος να καλύπτει ~12% του preview.
    final zoom = (0.12 / span).clamp(1.35, 3.2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        final viewportH = constraints.maxHeight;
        final scaledW = viewportW * zoom;
        final scaledH = viewportH * zoom;
        final targetX = cx * scaledW;
        final targetY = cy * scaledH;

        double dx = (viewportW / 2) - targetX;
        double dy = (viewportH / 2) - targetY;
        final minDx = viewportW - scaledW;
        final minDy = viewportH - scaledH;
        if (dx > 0) dx = 0;
        if (dy > 0) dy = 0;
        if (dx < minDx) dx = minDx;
        if (dy < minDy) dy = minDy;
        final overlayLeft = (nx * scaledW) + dx;
        final overlayTop = (ny * scaledH) + dy;
        final overlayWidth = nw * scaledW;
        final overlayHeight = nh * scaledH;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: Offset(dx, dy),
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: scaledW,
                  maxWidth: scaledW,
                  minHeight: scaledH,
                  maxHeight: scaledH,
                  child: SizedBox(
                    width: scaledW,
                    height: scaledH,
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: overlayLeft,
                top: overlayTop,
                width: overlayWidth,
                height: overlayHeight,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: SizedBox(
        width: _kCardWidth,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_MiniMapCardData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: _kSnapshotHeight + 44,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snapshot.data!;
              final activeMode = data.hasPhoneEquipmentToggle
                  ? _mode
                  : data.initialMode;
              final target = _targetForMode(data, activeMode);
              final pendingEntity = target.pendingEntity ?? target.departmentId;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.map, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          target.label,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (data.hasPhoneEquipmentToggle)
                        IconButton(
                          tooltip: activeMode == _MiniMapMode.equipment
                              ? 'Προβολή θέσης τηλεφώνου'
                              : 'Προβολή θέσης εξοπλισμού',
                          onPressed: () {
                            setState(() {
                              _mode = activeMode == _MiniMapMode.equipment
                                  ? _MiniMapMode.phone
                                  : _MiniMapMode.equipment;
                            });
                          },
                          icon: const Icon(Icons.swap_horiz),
                        ),
                      IconButton(
                        tooltip: 'Άνοιγμα πλήρους χάρτη',
                        onPressed: pendingEntity == null
                            ? null
                            : () async {
                                await showBuildingMapDialog(
                                  context,
                                  ref,
                                  pendingEntity: pendingEntity,
                                );
                              },
                        icon: const Icon(Icons.explore),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: _kSnapshotHeight,
                    width: _kCardWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildSnapshot(context, target, data),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MiniMapTarget {
  const _MiniMapTarget({
    required this.label,
    required this.departmentId,
    required this.pendingEntity,
  });

  final String label;
  final int? departmentId;
  final dynamic pendingEntity;
}

class _MiniMapCardData {
  const _MiniMapCardData({
    required this.floors,
    required this.departmentsById,
    required this.selectedDepartmentId,
    required this.hasPhoneEquipmentToggle,
    required this.initialMode,
    required this.equipmentEntity,
    required this.equipmentDepartmentId,
    required this.phoneDepartmentId,
    required this.userDepartmentId,
  });

  final List<BuildingMapFloor> floors;
  final Map<int, DepartmentModel> departmentsById;
  final int? selectedDepartmentId;
  final bool hasPhoneEquipmentToggle;
  final _MiniMapMode initialMode;
  final EquipmentModel? equipmentEntity;
  final int? equipmentDepartmentId;
  final int? phoneDepartmentId;
  final int? userDepartmentId;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
