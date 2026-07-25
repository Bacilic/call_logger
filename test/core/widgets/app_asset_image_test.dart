import 'package:call_logger/core/widgets/app_asset_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'AppAssetImage εμφανίζει fallbackIcon όταν το asset λείπει',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppAssetImage(
              assetPath: 'assets/__does_not_exist__.png',
              fallbackIcon: Icons.broken_image,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    },
  );
}
