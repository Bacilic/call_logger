import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../core/services/building_map_storage.dart';
import '../../models/department_model.dart';
import '../providers/building_map_providers.dart';
import 'building_map_sheet_painter.dart';

class _PreviewData {
  const _PreviewData({required this.file, required this.size});

  const _PreviewData.missing() : file = null, size = Size.zero;

  final File? file;
  final Size size;

  bool get missing => file == null || size.isEmpty;
}

/// Μικρογραφία ολόκληρης κατόψης για τον διάλογο επεξεργασίας (προαιρετικά τμήματα).
class BuildingMapFloorEditPreview extends StatefulWidget {
  const BuildingMapFloorEditPreview({
    super.key,
    required this.imagePath,
    required this.floorId,
    required this.rotationDegrees,
    required this.showDepartments,
    required this.departments,
  });

  final String imagePath;
  final int floorId;
  final double rotationDegrees;
  final bool showDepartments;
  final List<DepartmentModel> departments;

  static const double maxPreviewHeight = 280;

  /// Υπολογισμός διαστάσεων χωρίς [LayoutBuilder] (ασφαλές σε AlertDialog/ScrollView).
  static Size previewDisplaySize({
    required double maxContentWidth,
    required double aspectRatio,
  }) {
    var displayW = maxContentWidth;
    var displayH = maxContentWidth / aspectRatio;
    if (displayH > maxPreviewHeight) {
      displayH = maxPreviewHeight;
      displayW = displayH * aspectRatio;
    }
    return Size(displayW, displayH);
  }

  @override
  State<BuildingMapFloorEditPreview> createState() =>
      _BuildingMapFloorEditPreviewState();
}

class _BuildingMapFloorEditPreviewState extends State<BuildingMapFloorEditPreview> {
  Future<_PreviewData>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadPreview(widget.imagePath);
  }

  @override
  void didUpdateWidget(covariant BuildingMapFloorEditPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      setState(() {
        _loadFuture = _loadPreview(widget.imagePath);
      });
    }
  }

  Future<_PreviewData> _loadPreview(String imagePath) async {
    final trimmed = imagePath.trim();
    if (trimmed.isEmpty) return const _PreviewData.missing();

    late final File file;
    if (p.isAbsolute(trimmed)) {
      file = File(p.normalize(trimmed));
    } else {
      file = await BuildingMapStorage.fileForStoredPath(trimmed);
    }
    if (!await file.exists()) return const _PreviewData.missing();

    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return _PreviewData(file: file, size: size);
    } catch (_) {
      return const _PreviewData.missing();
    }
  }

  Set<int> _hiddenDepartmentIds() {
    final hidden = <int>{};
    for (final d in widget.departments) {
      if (!d.isHiddenOnMap) continue;
      final id = d.id;
      if (id != null) hidden.add(id);
    }
    return hidden;
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;

    return FutureBuilder<_PreviewData>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: 120,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null || data.missing) {
          return Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Δεν βρέθηκε εικόνα κατόψης.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          );
        }

        final aspect = data.size.width / data.size.height;
        final rotRad = widget.rotationDegrees * math.pi / 180;
        final sheetStr = widget.floorId.toString();

        final screenW = MediaQuery.sizeOf(context).width;
        final maxContentWidth = math.min(screenW - 80, 512).toDouble();
        final displaySize = BuildingMapFloorEditPreview.previewDisplaySize(
          maxContentWidth: maxContentWidth,
          aspectRatio: aspect.toDouble(),
        );

        return SizedBox(
          width: double.infinity,
          height: displaySize.height,
          child: Center(
            child: SizedBox(
              width: displaySize.width,
              height: displaySize.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: outline),
                  borderRadius: BorderRadius.circular(4),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.rotate(
                        angle: rotRad,
                        child: Image.file(
                          data.file!,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      if (widget.showDepartments)
                        CustomPaint(
                          painter: BuildingMapSheetPainter(
                            sheetIdString: sheetStr,
                            departments: widget.departments,
                            rotationRadians: rotRad,
                            toolMode: MapToolMode.select,
                            hiddenDepartmentIds: _hiddenDepartmentIds(),
                          ),
                          child: const SizedBox.expand(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
