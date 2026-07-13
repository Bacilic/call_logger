// Widget tests: Π1 — μετακίνηση (pan) χάρτη κατά τη σχεδίαση ορόφου.
// Μηχανισμοί: μεσαίο πλήκτρο ποντικιού, κρατημένο Space, διακόπτης εργαλειοθήκης.
// Το σχήμα του κέρσορα ΔΕΝ ελέγχεται εδώ (μη αποδείξιμο σε widget test στα Windows).
//
//   flutter test test/features/directory/building_map/building_map_sheet_viewport_pan_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:call_logger/features/directory/building_map/providers/building_map_providers.dart';
import 'package:call_logger/features/directory/building_map/widgets/building_map_sheet_viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Ελάχιστο έγκυρο PNG 1×1 pixel (base64).
const String _kTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<File> _createTempFloorImage() async {
  final bytes = base64Decode(_kTinyPngBase64);
  final file = File(
    '${Directory.systemTemp.path}/building_map_pan_test_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes);
  return file;
}

Future<ProviderContainer> _pumpViewport(
  WidgetTester tester, {
  required File imgFile,
  MapToolMode toolMode = MapToolMode.draw,
  bool withTextFieldAbove = false,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(buildingMapToolProvider.notifier).setMode(toolMode);
  container
      .read(buildingMapSelectedDepartmentIdToMapProvider.notifier)
      .setDept(1);

  final viewport = SizedBox(
    width: 600,
    height: 300,
    child: BuildingMapSheetViewport(
      designModeActive: true,
      sheetStr: '1',
      rotRad: 0,
      imgPath: imgFile.path,
      imgFile: imgFile,
      decodedSize: const Size(400, 250),
      activeDepartments: const [],
      currentSheetId: 1,
      onFloorsChanged: () {},
    ),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: withTextFieldAbove
              ? Column(
                  children: [
                    const TextField(
                      key: Key('pan_test_text_field'),
                    ),
                    viewport,
                  ],
                )
              : viewport,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

Future<void> _disposePumpedWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();
}

void main() {
  late File imgFile;

  setUp(() async {
    imgFile = await _createTempFloorImage();
  });

  tearDown(() async {
    if (imgFile.existsSync()) {
      await imgFile.delete();
    }
  });

  group('Π1 — pan κατά τη σχεδίαση', () {
    testWidgets(
      'μεσαίο πλήκτρο: σύρσιμο μετατοπίζει τον χάρτη χωρίς να δημιουργεί draft',
      (tester) async {
        final container = await _pumpViewport(tester, imgFile: imgFile);
        final controller = _viewer(tester).transformationController!;
        final before = controller.value.clone();

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(40, 25));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final after = controller.value;
        expect(
          after.getTranslation().x - before.getTranslation().x,
          closeTo(40, 0.001),
        );
        expect(
          after.getTranslation().y - before.getTranslation().y,
          closeTo(25, 0.001),
        );
        expect(container.read(buildingMapDraftShapeProvider), isNull);
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'Space κρατημένο: ενεργοποιεί panEnabled και το αριστερό σύρσιμο δεν σχεδιάζει',
      (tester) async {
        final container = await _pumpViewport(tester, imgFile: imgFile);
        expect(_viewer(tester).panEnabled, isFalse);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(_viewer(tester).panEnabled, isTrue);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(30, 10));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(container.read(buildingMapDraftShapeProvider), isNull);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(_viewer(tester).panEnabled, isFalse);
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'διακόπτης pan (provider): panEnabled ενεργό και χωρίς draft στο αριστερό σύρσιμο',
      (tester) async {
        final container = await _pumpViewport(tester, imgFile: imgFile);
        container.read(buildingMapPanLockProvider.notifier).setValue(true);
        await tester.pump();
        expect(_viewer(tester).panEnabled, isTrue);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await gesture.moveBy(const Offset(50, 20));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(container.read(buildingMapDraftShapeProvider), isNull);

        container.read(buildingMapPanLockProvider.notifier).setValue(false);
        await tester.pump();
        expect(_viewer(tester).panEnabled, isFalse);
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'Space μέσα σε εστιασμένο πεδίο κειμένου: ΔΕΝ ενεργοποιεί pan',
      (tester) async {
        await _pumpViewport(
          tester,
          imgFile: imgFile,
          withTextFieldAbove: true,
        );
        await tester.tap(find.byKey(const Key('pan_test_text_field')));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(_viewer(tester).panEnabled, isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'μεσαίο κλικ στη Σχεδίαση: δεν ξεκινά ορθογώνιο draft (μόνο αριστερό σχεδιάζει)',
      (tester) async {
        final container = await _pumpViewport(tester, imgFile: imgFile);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(InteractiveViewer)),
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.pump();
        expect(container.read(buildingMapDraftShapeProvider), isNull);
        await gesture.up();
        await tester.pump();
        await _disposePumpedWidget(tester);
      },
      semanticsEnabled: false,
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  });
}
