// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/building_map_repository.dart';
import '../../../../core/database/department_repository.dart';
import '../../../../core/database/directory_support.dart';
import '../../../../core/database/equipment_repository.dart';
import '../../../../core/database/sqlite_types.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../../../core/services/building_map_storage.dart';
import '../../../../core/services/lookup_service.dart';
import '../../../directory/building_map/screens/building_map_dialog.dart';
import '../../../directory/models/department_floor_display_extension.dart';
import '../../../directory/models/department_model.dart';
import '../../models/equipment_model.dart';
import '../../models/user_model.dart';

enum _MiniMapMode { department, equipment, phone, user }

class MiniMapCard extends ConsumerStatefulWidget {
  const MiniMapCard({
    super.key,
    required this.equipment,
    required this.equipmentCodeText,
    required this.phoneText,
    required this.user,
    this.callerDisplayText = '',
    this.departmentId,
  });

  final EquipmentModel? equipment;
  final String equipmentCodeText;
  final String phoneText;
  final UserModel? user;
  final String callerDisplayText;
  /// Selected department from header (priority source for map).
  final int? departmentId;

  @override
  ConsumerState<MiniMapCard> createState() => _MiniMapCardState();
}

class _MiniMapCardState extends ConsumerState<MiniMapCard> {
  static const double _kCardWidth = 336;
  static const double _kSnapshotHeight = 170;
  static const String _kDepartmentNotFoundAsset =
      'assets/department_not_found.png';
  static const String _kDepartmentNotOnMapMessage =
      'Δεν υπάρχει το τμήμα στο χάρτη';

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
        oldWidget.callerDisplayText != widget.callerDisplayText ||
        oldWidget.user?.id != widget.user?.id ||
        oldWidget.user?.departmentId != widget.user?.departmentId ||
        oldWidget.departmentId != widget.departmentId;
    if (changed) {
      _dataFuture = _loadData();
    }
  }

  Future<List<int>> _departmentIdsForPhone(
    DepartmentRepository departments,
    String phone,
  ) =>
      departments.resolveActiveDepartmentIdsForPhone(phone);

  Future<List<int>> _departmentIdsForEquipment(
    DepartmentRepository departments,
    EquipmentRepository equipmentRepo,
    EquipmentModel equipment,
  ) async {
    final direct = equipment.departmentId;
    if (direct != null) return [direct];
    final equipmentId = equipment.id;
    if (equipmentId == null) return const [];
    final linkedUsers = await equipmentRepo.getUserIdsLinkedToEquipment(
      equipmentId,
    );
    final ids = <int>{};
    for (final uid in linkedUsers) {
      ids.addAll(await departments.resolveActiveDepartmentIdsForUserId(uid));
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
    final departmentsRepo = DepartmentRepository(db);
    final equipmentRepo = EquipmentRepository(db);
    final floors =
        await BuildingMapRepository(db, DirectorySupport(db)).listBuildingMapFloors();
    final departmentRows = await departmentsRepo.getActiveDepartments();
    final departments = departmentRows
        .map(DepartmentModel.fromMap)
        .toList(growable: false);
    final byId = <int, DepartmentModel>{
      for (final d in departments)
        if (d.id != null) d.id!: d,
    };

    final equipment = await _resolveEquipment(db);
    final equipmentDeptIds = equipment == null
        ? const <int>[]
        : await _departmentIdsForEquipment(
            departmentsRepo,
            equipmentRepo,
            equipment,
          );
    final phoneDeptIds = await _departmentIdsForPhone(
      departmentsRepo,
      widget.phoneText,
    );

    final userDeptId = widget.user?.departmentId;
    final userDeptIds = userDeptId == null ? const <int>[] : <int>[userDeptId];

    final headerDeptId = widget.departmentId;
    final equipmentDeptId = equipmentDeptIds.isNotEmpty ? equipmentDeptIds.first : null;
    final phoneDeptId = phoneDeptIds.isNotEmpty ? phoneDeptIds.first : null;
    final userDeptFallback = userDeptIds.isNotEmpty ? userDeptIds.first : null;

    // Priority: Department → Equipment → Caller (design doc §7).
    _MiniMapMode mode = _MiniMapMode.department;
    if (headerDeptId == null) {
      mode = _MiniMapMode.equipment;
      if (equipmentDeptId == null && phoneDeptId != null) {
        mode = _MiniMapMode.phone;
      } else if (equipmentDeptId == null &&
          phoneDeptId == null &&
          userDeptFallback != null) {
        mode = _MiniMapMode.user;
      }
    }

    final hasToggle =
        equipmentDeptId != null &&
        phoneDeptId != null &&
        equipmentDeptId != phoneDeptId;
    final selectedDeptId = switch (mode) {
      _MiniMapMode.department => headerDeptId ?? equipmentDeptId ?? userDeptFallback ?? phoneDeptId,
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

  DepartmentModel? _departmentForTarget(
    _MiniMapCardData data,
    _MiniMapTarget target,
  ) {
    final deptId = target.departmentId;
    if (deptId == null) return null;
    return data.departmentsById[deptId];
  }

  String? _floorDisplayName(
    _MiniMapCardData data,
    DepartmentModel? dept,
  ) {
    if (dept == null) return null;
    final floorById = {for (final f in data.floors) f.id: f};
    return dept.floorDisplayWithCatalog(floorById);
  }

  String? _registeredCallerName() {
    final fromUser = widget.user?.name?.trim();
    if (fromUser != null && fromUser.isNotEmpty) return fromUser;
    final fromText = widget.callerDisplayText.trim();
    if (fromText.isNotEmpty) return fromText;
    return null;
  }

  String _snapshotTooltip(_MiniMapCardData data, _MiniMapTarget target) {
    final dept = _departmentForTarget(data, target);
    if (dept == null) {
      return 'Δεν βρέθηκε συσχετισμένο τμήμα για ${target.label.toLowerCase()}.';
    }
    final lines = <String>[
      dept.displayName,
      if (_floorDisplayName(data, dept) case final floor?) 'Όροφος: $floor',
      ?_registeredCallerName(),
      if (!dept.isMapped) 'Το τμήμα δεν υπάρχει στον χάρτη κτιρίου.',
    ];
    return lines.join('\n');
  }

  String _exploreTooltip(
    _MiniMapCardData data,
    _MiniMapTarget target,
    dynamic pendingEntity,
  ) {
    if (pendingEntity == null) {
      return 'Δεν υπάρχει επιλογή για άνοιγμα χάρτη.\n'
          'Συμπληρώστε εξοπλισμό, τηλέφωνο ή υπάλληλο.';
    }
    final dept = _departmentForTarget(data, target);
    final lines = <String>['Άνοιγμα πλήρους χάρτη κτιρίου'];
    if (dept != null) {
      lines.add('Τμήμα: ${dept.displayName}');
      final floor = _floorDisplayName(data, dept);
      if (floor != null) lines.add('Όροφος: $floor');
    }
    return lines.join('\n');
  }

  String _swapTooltip(_MiniMapCardData data, _MiniMapMode activeMode) {
    if (activeMode == _MiniMapMode.equipment) {
      final dept = data.phoneDepartmentId == null
          ? null
          : data.departmentsById[data.phoneDepartmentId!];
      if (dept != null) {
        return 'Εναλλαγή σε θέση τηλεφώνου\nΤμήμα: ${dept.displayName}';
      }
      return 'Προβολή θέσης τηλεφώνου';
    }
    final dept = data.equipmentDepartmentId == null
        ? null
        : data.departmentsById[data.equipmentDepartmentId!];
    if (dept != null) {
      return 'Εναλλαγή σε θέση εξοπλισμού\nΤμήμα: ${dept.displayName}';
    }
    return 'Προβολή θέσης εξοπλισμού';
  }

  _MiniMapTarget _targetForMode(
    _MiniMapCardData data,
    _MiniMapMode mode,
  ) {
    final fallback = data.selectedDepartmentId;
    if (mode == _MiniMapMode.department) {
      return _MiniMapTarget(
        label: 'Θέση τμήματος',
        departmentId: widget.departmentId ?? fallback,
        pendingEntity: widget.departmentId,
      );
    }
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
    if (!dept.isMapped) {
      return _departmentNotOnMap(context);
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
    final storedImagePath = floor.imagePath.trim();
    if (storedImagePath.isEmpty) {
      return _placeholder(context, 'Δεν βρέθηκε αρχείο κατόψης.');
    }

    return FutureBuilder<String>(
      key: ValueKey<String>(storedImagePath),
      future: BuildingMapStorage.resolveToAbsolute(storedImagePath),
      builder: (context, pathSnap) {
        if (!pathSnap.hasData) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final imagePath = pathSnap.data!;
        if (imagePath.isEmpty || !File(imagePath).existsSync()) {
          return _placeholder(context, 'Δεν βρέθηκε αρχείο κατόψης.');
        }
        return _buildMappedFloorPreview(
          context,
          dept: dept,
          floor: floor,
          imagePath: imagePath,
        );
      },
    );
  }

  Widget _buildMappedFloorPreview(
    BuildContext context, {
    required DepartmentModel dept,
    required BuildingMapFloor floor,
    required String imagePath,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MiniMapFloorPreview(
          dept: dept,
          imagePath: imagePath,
          viewportWidth: constraints.maxWidth,
          viewportHeight: constraints.maxHeight,
        );
      },
    );
  }

  Widget _departmentNotOnMap(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              _kDepartmentNotFoundAsset,
              height: 96,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(height: 8),
            Text(
              _kDepartmentNotOnMapMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
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
              final mapJumpEntity = target.departmentId ?? target.pendingEntity;

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
                          tooltip: _swapTooltip(data, activeMode),
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
                        tooltip: _exploreTooltip(data, target, mapJumpEntity),
                        onPressed: mapJumpEntity == null
                            ? null
                            : () async {
                                await showBuildingMapDialog(
                                  context,
                                  ref,
                                  pendingEntity: mapJumpEntity,
                                );
                              },
                        icon: const Icon(Icons.explore),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Tooltip(
                    message: _snapshotTooltip(data, target),
                    waitDuration: const Duration(milliseconds: 350),
                    showDuration: const Duration(seconds: 10),
                    child: SizedBox(
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

/// Διαδραστική προεπισκόπηση κατόψεως με επισήμανση τμήματος (μικρός χάρτης κλήσεων).
@visibleForTesting
class MiniMapFloorPreview extends StatefulWidget {
  const MiniMapFloorPreview({
    super.key,
    required this.dept,
    required this.imagePath,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  static const double kMinInteractiveScale = 1.0;
  static const double kMaxInteractiveScale = 6.0;
  static const double _kTargetDepartmentCoverage = 0.12;
  static const double _kMinBaseZoom = 1.35;
  static const double _kMaxBaseZoom = 3.2;
  static const int _kImageDecodeCeilingPx = 2048;
  static const double _kWheelZoomFactor = 0.12;

  final DepartmentModel dept;
  final String imagePath;
  final double viewportWidth;
  final double viewportHeight;

  @override
  State<MiniMapFloorPreview> createState() => _MiniMapFloorPreviewState();
}

class _MiniMapFloorPreviewState extends State<MiniMapFloorPreview> {
  late final TransformationController _transformationController;
  late Matrix4 _initialMatrix;
  late _MiniMapFloorPreviewLayout _layout;
  DateTime? _lastPointerUpTime;
  int _pointerUpCount = 0;

  @override
  void initState() {
    super.initState();
    _layout = _MiniMapFloorPreviewLayout.compute(
      dept: widget.dept,
      viewportWidth: widget.viewportWidth,
      viewportHeight: widget.viewportHeight,
    );
    _initialMatrix = _layout.initialMatrix;
    _transformationController = TransformationController(_initialMatrix);
  }

  @override
  void didUpdateWidget(covariant MiniMapFloorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layoutChanged =
        oldWidget.dept.id != widget.dept.id ||
        oldWidget.dept.mapX != widget.dept.mapX ||
        oldWidget.dept.mapY != widget.dept.mapY ||
        oldWidget.dept.mapWidth != widget.dept.mapWidth ||
        oldWidget.dept.mapHeight != widget.dept.mapHeight ||
        oldWidget.dept.mapRotation != widget.dept.mapRotation ||
        oldWidget.imagePath != widget.imagePath ||
        oldWidget.viewportWidth != widget.viewportWidth ||
        oldWidget.viewportHeight != widget.viewportHeight;
    if (!layoutChanged) return;

    _layout = _MiniMapFloorPreviewLayout.compute(
      dept: widget.dept,
      viewportWidth: widget.viewportWidth,
      viewportHeight: widget.viewportHeight,
    );
    _initialMatrix = _layout.initialMatrix;
    _transformationController.value = _initialMatrix;
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetTransform() {
    _transformationController.value = _initialMatrix;
  }

  void _onPointerUp(PointerUpEvent event) {
    final now = DateTime.now();
    if (_lastPointerUpTime != null &&
        now.difference(_lastPointerUpTime!) <=
            const Duration(milliseconds: 350)) {
      _pointerUpCount++;
    } else {
      _pointerUpCount = 1;
    }
    _lastPointerUpTime = now;
    if (_pointerUpCount >= 2) {
      _pointerUpCount = 0;
      _lastPointerUpTime = null;
      _resetTransform();
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final scrollDelta = event.scrollDelta.dy;
    if (scrollDelta == 0) return;

    final current = _transformationController.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    final scaleDelta = scrollDelta > 0
        ? (1 - MiniMapFloorPreview._kWheelZoomFactor)
        : (1 + MiniMapFloorPreview._kWheelZoomFactor);
    final newScale = (currentScale * scaleDelta).clamp(
      MiniMapFloorPreview.kMinInteractiveScale,
      MiniMapFloorPreview.kMaxInteractiveScale,
    );
    if ((newScale - currentScale).abs() < 1e-6) return;

    final focalPoint = event.localPosition;
    final scaleChange = newScale / currentScale;
    final updated = Matrix4.copy(current)
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(scaleChange)
      ..translate(-focalPoint.dx, -focalPoint.dy);
    _transformationController.value = updated;
  }

  Widget _departmentHighlight(BuildContext context) {
    final highlight = DecoratedBox(
      key: const Key('mini_map_department_highlight'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
    );

    final rotation = widget.dept.mapRotation;
    if (rotation == 0) return highlight;

    return Transform.rotate(
      angle: rotation,
      alignment: Alignment.center,
      child: highlight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = math.min(
      MiniMapFloorPreview._kImageDecodeCeilingPx,
      (_layout.viewportWidth *
              2 *
              dpr *
              MiniMapFloorPreview.kMaxInteractiveScale)
          .round(),
    );

    return ClipRect(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.viewportWidth,
          height: widget.viewportHeight,
          child: Listener(
            key: const Key('mini_map_scroll_listener'),
            behavior: HitTestBehavior.opaque,
            onPointerUp: _onPointerUp,
            onPointerSignal: _onPointerSignal,
            child: InteractiveViewer(
                key: const Key('mini_map_interactive_viewer'),
                transformationController: _transformationController,
                minScale: MiniMapFloorPreview.kMinInteractiveScale,
                maxScale: MiniMapFloorPreview.kMaxInteractiveScale,
                constrained: false,
                clipBehavior: Clip.hardEdge,
                panEnabled: true,
                scaleEnabled: false,
                boundaryMargin: EdgeInsets.zero,
                child: SizedBox(
                  width: _layout.scaledWidth,
                  height: _layout.scaledHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        cacheWidth: cacheWidth,
                      ),
                      Positioned(
                        left: _layout.highlightLeft,
                        top: _layout.highlightTop,
                        width: _layout.highlightWidth,
                        height: _layout.highlightHeight,
                        child: IgnorePointer(
                          child: _departmentHighlight(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _MiniMapFloorPreviewLayout {
  const _MiniMapFloorPreviewLayout({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.highlightLeft,
    required this.highlightTop,
    required this.highlightWidth,
    required this.highlightHeight,
    required this.initialMatrix,
  });

  final double viewportWidth;
  final double viewportHeight;
  final double scaledWidth;
  final double scaledHeight;
  final double highlightLeft;
  final double highlightTop;
  final double highlightWidth;
  final double highlightHeight;
  final Matrix4 initialMatrix;

  static double _rotatedSpan(double width, double height, double radians) {
    final cosA = math.cos(radians).abs();
    final sinA = math.sin(radians).abs();
    final rotatedWidth = (width * cosA) + (height * sinA);
    final rotatedHeight = (width * sinA) + (height * cosA);
    return rotatedWidth > rotatedHeight ? rotatedWidth : rotatedHeight;
  }

  static Matrix4 _initialTranslationMatrix({
    required double viewportWidth,
    required double viewportHeight,
    required double scaledWidth,
    required double scaledHeight,
    required double centerX,
    required double centerY,
  }) {
    final targetX = centerX * scaledWidth;
    final targetY = centerY * scaledHeight;

    var dx = (viewportWidth / 2) - targetX;
    var dy = (viewportHeight / 2) - targetY;
    final minDx = viewportWidth - scaledWidth;
    final minDy = viewportHeight - scaledHeight;
    if (dx > 0) dx = 0;
    if (dy > 0) dy = 0;
    if (dx < minDx) dx = minDx;
    if (dy < minDy) dy = minDy;

    return Matrix4.identity()..translate(dx, dy);
  }

  static _MiniMapFloorPreviewLayout compute({
    required DepartmentModel dept,
    required double viewportWidth,
    required double viewportHeight,
  }) {
    final nx = dept.mapX!;
    final ny = dept.mapY!;
    final nw = dept.mapWidth!;
    final nh = dept.mapHeight!;

    final cx = (nx + (nw / 2)).clamp(0.0, 1.0);
    final cy = (ny + (nh / 2)).clamp(0.0, 1.0);
    final span = _rotatedSpan(nw, nh, dept.mapRotation);
    final zoom = (MiniMapFloorPreview._kTargetDepartmentCoverage / span).clamp(
      MiniMapFloorPreview._kMinBaseZoom,
      MiniMapFloorPreview._kMaxBaseZoom,
    );

    final scaledWidth = viewportWidth * zoom;
    final scaledHeight = viewportHeight * zoom;
    final initialMatrix = _initialTranslationMatrix(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      scaledWidth: scaledWidth,
      scaledHeight: scaledHeight,
      centerX: cx,
      centerY: cy,
    );

    return _MiniMapFloorPreviewLayout(
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      scaledWidth: scaledWidth,
      scaledHeight: scaledHeight,
      highlightLeft: nx * scaledWidth,
      highlightTop: ny * scaledHeight,
      highlightWidth: nw * scaledWidth,
      highlightHeight: nh * scaledHeight,
      initialMatrix: initialMatrix,
    );
  }
}
