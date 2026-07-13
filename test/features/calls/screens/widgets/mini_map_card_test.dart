// Widget tests: περιστροφή επισήμανσης τμήματος και διαδραστικό zoom/pan στον μικρό χάρτη.
//
//   flutter test test/features/calls/screens/widgets/mini_map_card_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:call_logger/features/calls/screens/widgets/mini_map_card.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


/// Ελάχιστο έγκυρο PNG 1×1 pixel (base64).
const String _kTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const double _kTestViewportWidth = 336;
const double _kTestViewportHeight = 170;

DepartmentModel _mappedDepartment({
  double mapRotation = 0.0,
}) {
  return DepartmentModel(
    id: 1,
    name: 'Τμήμα δοκιμής',
    mapFloor: '1',
    mapX: 0.35,
    mapY: 0.4,
    mapWidth: 0.18,
    mapHeight: 0.12,
    mapRotation: mapRotation,
  );
}

Future<String> _createTempFloorImage() async {
  final bytes = base64Decode(_kTinyPngBase64);
  final file = File(
    '${Directory.systemTemp.path}/mini_map_test_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}

Finder _highlightRotationTransformFinder() {
  return find.ancestor(
    of: find.byKey(const Key('mini_map_department_highlight')),
    matching: find.byWidgetPredicate((widget) {
      if (widget is! Transform) return false;
      return _matrixRotationZ(widget.transform).abs() > 1e-6;
    }),
  );
}

double _matrixRotationZ(Matrix4 matrix) {
  return math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));
}

Future<void> _dispatchScroll(
  WidgetTester tester,
  Offset position,
  double deltaY,
) async {
  final binding = tester.binding;
  final result = HitTestResult();
  // ignore: deprecated_member_use
  binding.hitTest(result, position);
  binding.handlePointerEvent(
    PointerScrollEvent(
      timeStamp: Duration.zero,
      position: position,
      scrollDelta: Offset(0, deltaY),
    ),
  );
  await tester.pump();
}

Future<void> _pumpMiniMapFloorPreview(
  WidgetTester tester, {
  required DepartmentModel dept,
  required String imagePath,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: _kTestViewportWidth,
          height: _kTestViewportHeight,
          child: MiniMapFloorPreview(
            dept: dept,
            imagePath: imagePath,
            viewportWidth: _kTestViewportWidth,
            viewportHeight: _kTestViewportHeight,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _disposePumpedWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();
}

void main() {
  late String imagePath;

  setUp(() async {
    imagePath = await _createTempFloorImage();
  });

  group('Δ6 — περιστροφή επισήμανσης τμήματος', () {
    testWidgets(
      'τμήμα με mapRotation ≠ 0 φέρει Transform.rotate γύρω από το κέντρο',
      (tester) async {
        const rotation = 0.75;
        await _pumpMiniMapFloorPreview(
          tester,
          dept: _mappedDepartment(mapRotation: rotation),
          imagePath: imagePath,
        );

        final rotationFinder = _highlightRotationTransformFinder();
        expect(rotationFinder, findsOneWidget);
        final transform = tester.widget<Transform>(rotationFinder);
        expect(transform.alignment, Alignment.center);
        expect(
          _matrixRotationZ(transform.transform),
          closeTo(rotation, 0.001),
        );
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'τμήμα με μηδενική περιστροφή — χωρίς Transform.rotate στην επισήμανση',
      (tester) async {
        await _pumpMiniMapFloorPreview(
          tester,
          dept: _mappedDepartment(mapRotation: 0.0),
          imagePath: imagePath,
        );

        expect(_highlightRotationTransformFinder(), findsNothing);

        final positioned = tester.widget<Positioned>(
          find.ancestor(
            of: find.byKey(const Key('mini_map_department_highlight')),
            matching: find.byType(Positioned),
          ),
        );
        final dept = _mappedDepartment(mapRotation: 0.0);
        final span = dept.mapWidth! > dept.mapHeight!
            ? dept.mapWidth!
            : dept.mapHeight!;
        final zoom = (0.12 / span).clamp(1.35, 3.2);
        final scaledW = _kTestViewportWidth * zoom;
        final scaledH = _kTestViewportHeight * zoom;

        expect(positioned.left, closeTo(dept.mapX! * scaledW, 0.5));
        expect(positioned.top, closeTo(dept.mapY! * scaledH, 0.5));
        expect(positioned.width, closeTo(dept.mapWidth! * scaledW, 0.5));
        expect(positioned.height, closeTo(dept.mapHeight! * scaledH, 0.5));
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
    );
  });

  group('Π2 — διαδραστικό zoom/pan (λογική controller)', () {
    // Η οπτική ομαλότητα (χωρίς κολλήματα) επιβεβαιώνεται χειροκίνητα στα Windows·
    // το τεστ αποδεικνύει μόνο τη λογική του TransformationController.

    testWidgets(
      'τροχός ποντικιού αλλάζει την κλίμακα εντός ορίων',
      (tester) async {
        await _pumpMiniMapFloorPreview(
          tester,
          dept: _mappedDepartment(),
          imagePath: imagePath,
        );

        final viewerFinder = find.byKey(const Key('mini_map_interactive_viewer'));
        expect(viewerFinder, findsOneWidget);
        final viewer = tester.widget<InteractiveViewer>(viewerFinder);
        final controller = viewer.transformationController!;
        final initialScale = controller.value.getMaxScaleOnAxis();

        final center = tester.getCenter(
          find.byKey(const Key('mini_map_scroll_listener')),
        );
        await _dispatchScroll(tester, center, -80);

        final afterZoomIn = controller.value.getMaxScaleOnAxis();
        expect(afterZoomIn, greaterThan(initialScale));
        expect(afterZoomIn, lessThanOrEqualTo(MiniMapFloorPreview.kMaxInteractiveScale));

        await _dispatchScroll(tester, center, 4000);
        await tester.pump();

        final afterZoomOut = controller.value.getMaxScaleOnAxis();
        expect(afterZoomOut, greaterThanOrEqualTo(MiniMapFloorPreview.kMinInteractiveScale));
        expect(afterZoomOut, lessThanOrEqualTo(MiniMapFloorPreview.kMaxInteractiveScale));
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
    );

    testWidgets('διπλό κλικ επαναφέρει την αρχική μετασχηματιστική τιμή', (
      tester,
    ) async {
      await _pumpMiniMapFloorPreview(
        tester,
        dept: _mappedDepartment(),
        imagePath: imagePath,
      );

      final viewerFinder = find.byKey(const Key('mini_map_interactive_viewer'));
      final viewer = tester.widget<InteractiveViewer>(viewerFinder);
      final controller = viewer.transformationController!;
      final initial = Matrix4.copy(controller.value);

      final center = tester.getCenter(
        find.byKey(const Key('mini_map_scroll_listener')),
      );
      await _dispatchScroll(tester, center, -120);
      expect(controller.value, isNot(equals(initial)));

      await tester.tapAt(center);
      await tester.pump();
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.value, equals(initial));
      await _disposePumpedWidget(tester);
    }, semanticsEnabled: false);
  });
}
