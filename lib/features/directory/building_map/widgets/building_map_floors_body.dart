import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';
import '../../providers/department_directory_provider.dart';
import '../controllers/building_map_controller.dart';
import '../providers/building_map_providers.dart';
import 'building_map_empty_canvas_message.dart';
import 'building_map_floor_menu_button.dart';
import 'building_map_omnisearch_field.dart';
import 'building_map_sheet_viewport.dart';
import 'map_rotation_pod.dart';
import 'department_selection_overlay.dart';
import 'views/building_map_edit_layout.dart';
import 'views/building_map_view_layout.dart';

/// Φορτώνει την λίστα ορόφων και συνθέτει τα layouts προβολής / επεξεργασίας και τον καμβά.
class BuildingMapFloorsBody extends ConsumerStatefulWidget {
  const BuildingMapFloorsBody({super.key, required this.repo});

  final DirectoryRepository repo;

  @override
  ConsumerState<BuildingMapFloorsBody> createState() =>
      _BuildingMapFloorsBodyState();
}

class _BuildingMapFloorsBodyState extends ConsumerState<BuildingMapFloorsBody> {
  final TextEditingController _globalSearchController = TextEditingController();
  final FocusNode _globalSearchFocusNode = FocusNode();

  String? _scheduledDecodePath;

  @override
  void dispose() {
    _globalSearchController.dispose();
    _globalSearchFocusNode.dispose();
    super.dispose();
  }

  void _scheduleDecodeForCurrentPath(String imgPath) {
    if (_scheduledDecodePath == imgPath) return;
    _scheduledDecodePath = imgPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(buildingMapControllerProvider).decodeImageForPath(imgPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reloadSeq = ref.watch(buildingMapFloorReloadSeqProvider);
    final editMode = ref.watch(buildingMapUiEditModeProvider);
    final deptHudVisible = ref.watch(
      buildingMapDeptSelectionHudVisibleProvider,
    );
    final decodedSize = ref.watch(buildingMapDecodedImageSizeProvider);
    final deptState = ref.watch(departmentDirectoryProvider);
    final sheetId = ref.watch(buildingMapSelectedSheetIdProvider);

    final activeDepartments = deptState.allDepartments
        .where((d) => !d.isDeleted)
        .toList();
    final controller = ref.read(buildingMapControllerProvider);

    return FutureBuilder<List<BuildingMapFloor>>(
      key: ValueKey<int>(reloadSeq),
      future: widget.repo.listBuildingMapFloors(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final floors = snap.data ?? [];

        if (floors.isEmpty) {
          controller.appliedInitialFloorSync = false;
          if (sheetId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(buildingMapSelectedSheetIdProvider.notifier)
                  .setSheet(null);
              if (mounted) setState(() {});
            });
          }
        } else if (!controller.appliedInitialFloorSync) {
          controller.appliedInitialFloorSync = true;
          Future.microtask(() async {
            await controller.syncSheetSelection(floors);
            if (mounted) setState(() {});
          });
        }

        BuildingMapFloor? current;
        if (floors.isNotEmpty) {
          for (final f in floors) {
            if (f.id == sheetId) {
              current = f;
              break;
            }
          }
          current ??= floors.first;
        }

        final int? currentSheetId = current?.id;
        if (currentSheetId != null && sheetId != currentSheetId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(buildingMapSelectedSheetIdProvider.notifier)
                .setSheet(currentSheetId);
          });
        }

        final sheetStr = currentSheetId?.toString() ?? '';
        final rotRad = (current?.rotationDegrees ?? 0) * math.pi / 180;
        final imgPath = current?.imagePath ?? '';
        final imgFile = File(imgPath);

        final imgExists = imgPath.isNotEmpty && imgFile.existsSync();
        final sz = decodedSize;
        final hasActiveCanvas = current != null && imgExists && sz != null;

        _scheduleDecodeForCurrentPath(imgPath);

        final sheetDropdownPlaceholder = InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Φύλλο κατόψης',
            border: OutlineInputBorder(),
            enabled: false,
          ),
          child: const SizedBox(height: 20),
        );

        final Widget sheetPickerControl = floors.isEmpty
            ? sheetDropdownPlaceholder
            : DropdownButtonFormField<int>(
                key: ValueKey<int>(currentSheetId!),
                initialValue: currentSheetId,
                decoration: const InputDecoration(
                  labelText: 'Φύλλο κατόψης',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final fl in floors)
                    DropdownMenuItem(
                      value: fl.id,
                      child: Text(
                        buildingMapFloorDisplayLabel(fl),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await controller.selectFloorFromList(v, floors);
                  if (mounted) setState(() {});
                },
              );

        final globalSearchField = BuildingMapOmnisearchField(
          enabled: floors.isNotEmpty,
          repo: widget.repo,
          controller: _globalSearchController,
          focusNode: _globalSearchFocusNode,
          onResolveEntity: (entity) =>
              controller.resolveAndJumpToEntity(context, entity),
        );

        void onFloorsMutated() {
          if (mounted) setState(() {});
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (editMode)
              BuildingMapEditLayout(
                floors: floors,
                hasActiveCanvas: hasActiveCanvas,
                activeDepartments: activeDepartments,
                currentSheetId: currentSheetId,
                onFloorsChanged: onFloorsMutated,
              ),
            if (!editMode)
              BuildingMapViewLayout(
                sheetPicker: sheetPickerControl,
                globalSearchField: globalSearchField,
                currentFloorLabel: current == null
                    ? null
                    : buildingMapFloorDisplayLabel(current),
              ),
            Expanded(
              child: floors.isEmpty
                  ? BuildingMapEmptyCanvasMessage(viewMode: !editMode)
                  : Stack(
                      clipBehavior: Clip.hardEdge,
                      fit: StackFit.expand,
                      children: [
                        BuildingMapSheetViewport(
                          designModeActive: editMode,
                          sheetStr: sheetStr,
                          rotRad: rotRad,
                          imgPath: imgPath,
                          imgFile: imgFile,
                          decodedSize: decodedSize,
                          activeDepartments: activeDepartments,
                          currentSheetId: currentSheetId,
                          onFloorsChanged: onFloorsMutated,
                        ),
                        if (editMode &&
                            currentSheetId != null &&
                            current != null)
                          Consumer(
                            builder: (context, ref, child) {
                              final dragRotation = ref.watch(
                                buildingMapDragRotationProvider,
                              );
                              return Positioned(
                                bottom: 24,
                                right: 24,
                                child: MapRotationPod(
                                  rotationDegrees:
                                      dragRotation ?? current!.rotationDegrees,
                                  enabled: hasActiveCanvas,
                                  onRotationChanged: (v) {
                                    ref
                                        .read(
                                          buildingMapDragRotationProvider
                                              .notifier,
                                        )
                                        .setRotation(v);
                                  },
                                  onRotationChangeEnd: (v) {
                                    ref
                                        .read(
                                          buildingMapDragRotationProvider
                                              .notifier,
                                        )
                                        .setRotation(null);
                                    controller.applySheetRotation(
                                      currentSheetId,
                                      v,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        if (editMode &&
                            deptHudVisible &&
                            currentSheetId != null)
                          Positioned.fill(
                            child: DepartmentSelectionOverlay(
                              activeDepartments: activeDepartments,
                              floors: floors,
                              onClose: () {
                                ref
                                    .read(
                                      buildingMapDeptSelectionHudVisibleProvider
                                          .notifier,
                                    )
                                    .setVisible(false);
                                ref
                                    .read(buildingMapToolProvider.notifier)
                                    .setMode(MapToolMode.draw);
                              },
                              onSelectDepartment: (id) {
                                ref
                                    .read(
                                      buildingMapSelectedDepartmentIdToMapProvider
                                          .notifier,
                                    )
                                    .setDept(id);
                                controller.syncDraftWithSelectedDepartment(
                                  departments: activeDepartments,
                                  departmentId: id,
                                  floorId: currentSheetId,
                                );
                                ref
                                    .read(
                                      buildingMapDeptSelectionHudVisibleProvider
                                          .notifier,
                                    )
                                    .setVisible(false);
                                ref
                                    .read(buildingMapToolProvider.notifier)
                                    .setMode(
                                      ref.read(buildingMapDraftShapeProvider) != null
                                          ? MapToolMode.edit
                                          : MapToolMode.draw,
                                    );
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
