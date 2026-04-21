import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/directory_repository.dart';
import '../../../../core/models/building_map_floor.dart';
import '../controllers/building_map_controller.dart';
import '../providers/building_map_providers.dart';
import '../widgets/building_map_floors_body.dart';

Future<void> showBuildingMapDialog(
  BuildContext context,
  WidgetRef ref, {
  dynamic pendingEntity,
}) async {
  ref.read(buildingMapSelectedDepartmentIdToMapProvider.notifier).setDept(null);
  ref.read(buildingMapToolProvider.notifier).setMode(MapToolMode.select);
  ref.read(buildingMapDraftShapeProvider.notifier).clear();
  ref.read(buildingMapEditFromSelectionTapProvider.notifier).clear();
  ref.read(buildingMapUndoProvider.notifier).clear();
  ref.read(buildingMapUiEditModeProvider.notifier).setEditing(false);
  ref.read(buildingMapDecodedImageSizeProvider.notifier).setSize(null);
  ref.read(buildingMapFloorReloadSeqProvider.notifier).reset();
  ref
      .read(buildingMapDeptSelectionHudVisibleProvider.notifier)
      .setVisible(false);
  final pendingJump = ref.read(buildingMapPendingJumpProvider.notifier);
  pendingJump.clear();
  if (pendingEntity != null) {
    pendingJump.setEntity(pendingEntity);
  }
  ref.read(buildingMapControllerProvider).resetSession();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (ctx) => const Dialog.fullscreen(child: BuildingMapDialog()),
  );
}

/// Κέλυφας fullscreen· εναλλαγή προβολής / επεξεργασίας μέσω [buildingMapUiEditModeProvider].
class BuildingMapDialog extends ConsumerWidget {
  const BuildingMapDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final floorsAsync = ref.watch(buildingMapDirectoryRepositoryProvider);
    final editMode = ref.watch(buildingMapUiEditModeProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: editMode
            ? _buildingMapEditModeTitle(ref)
            : const Text('Προβολή χάρτη'),
        actions: [
          if (editMode)
            IconButton(
              tooltip: 'Αναίρεση τελευταίας γεωμετρίας',
              onPressed: ref.watch(buildingMapUndoProvider) == null
                  ? null
                  : () => ref
                        .read(buildingMapControllerProvider)
                        .undoLastGeometry(context),
              icon: const Icon(Icons.undo),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Προβολή')),
                ButtonSegment(value: true, label: Text('Επεξεργασία')),
              ],
              selected: {editMode},
              onSelectionChanged: (selected) {
                final next = selected.first;
                ref
                    .read(buildingMapUiEditModeProvider.notifier)
                    .setEditing(next);
                if (!next) {
                  ref
                      .read(buildingMapDeptSelectionHudVisibleProvider.notifier)
                      .setVisible(false);
                  ref
                      .read(buildingMapToolProvider.notifier)
                      .setMode(MapToolMode.select);
                  ref.read(buildingMapDraftShapeProvider.notifier).clear();
                  ref
                      .read(buildingMapEditFromSelectionTapProvider.notifier)
                      .clear();
                }
              },
            ),
          ),
        ],
      ),
      body: floorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Σφάλμα: $e')),
        data: (repo) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final payload = ref
                .read(buildingMapPendingJumpProvider.notifier)
                .consume();
            if (payload == null || !context.mounted) return;
            ref
                .read(buildingMapControllerProvider)
                .resolveAndJumpToEntity(context, payload.entity);
          });
          return BuildingMapFloorsBody(repo: repo);
        },
      ),
    );
  }
}

/// Τίτλος AppBar σε λειτουργία επεξεργασίας: εμφανίζει τον ενεργό όροφο / φύλλο κατόψης.
Widget _buildingMapEditModeTitle(WidgetRef ref) {
  final reloadSeq = ref.watch(buildingMapFloorReloadSeqProvider);
  final sheetId = ref.watch(buildingMapSelectedSheetIdProvider);
  final repoAsync = ref.watch(buildingMapDirectoryRepositoryProvider);

  Widget fallback() => const Text('Επεξεργασία Χάρτη');

  return repoAsync.when(
    data: (DirectoryRepository repo) {
      return FutureBuilder<List<BuildingMapFloor>>(
        key: ValueKey<int>(reloadSeq),
        future: repo.listBuildingMapFloors(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return fallback();
          final floors = snapshot.data!;
          String? floorLabel;
          if (sheetId != null) {
            for (final f in floors) {
              if (f.id == sheetId) {
                floorLabel = f.label;
                break;
              }
            }
          }
          final name = floorLabel?.trim();
          if (name == null || name.isEmpty) return fallback();
          return Text('Επεξεργασία Χάρτη: $name');
        },
      );
    },
    loading: () => fallback(),
    error: (_, _) => fallback(),
  );
}
