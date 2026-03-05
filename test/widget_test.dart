// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.
//
// For key events: always send keyUp AFTER keyDown (e.g. sendKeyDownEvent then
// sendKeyUpEvent) so the key sequence is correct. See docs/KEYBOARD_AND_FOCUS.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:call_logger/main.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/init/app_initializer.dart';
import 'package:call_logger/core/init/app_init_provider.dart';

void main() {
  testWidgets('App shows main shell and call entry fields', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appInitProvider.overrideWith(
            (ref) => Future.value(AppInitResult(
              result: DatabaseInitResult.success(),
              isLocalDevMode: false,
            )),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Η σύνδεση με τη βάση δεδομένων πέτυχε.'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
