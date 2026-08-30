// Πού στέλνει το κουμπί «Μετάβαση στη ρύθμιση» κάθε είδους εύρημα διαδρομής.
//
//   flutter test test/features/directory/services/path_fix_navigator_test.dart

import 'package:call_logger/core/providers/database_settings_route_intent_provider.dart';
import 'package:call_logger/core/providers/main_nav_request_provider.dart';
import 'package:call_logger/core/providers/settings_route_intent_provider.dart';
import 'package:call_logger/core/widgets/main_nav_destination.dart';
import 'package:call_logger/features/directory/providers/remote_tools_view_intent_provider.dart';
import 'package:call_logger/features/directory/services/path_fix_destination.dart';
import 'package:call_logger/features/directory/services/path_fix_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ελάχιστο περιβάλλον που δίνει έναν [WidgetRef] χωρίς να χτίζει οθόνη.
Future<WidgetRef> _pumpRef(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          captured = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  testWidgets(
    'ο φάκελος αντιγράφων ανοίγει τις ρυθμίσεις βάσης στα αντίγραφα',
    (tester) async {
      final ref = await _pumpRef(tester, container);

      requestPathFixNavigation(ref, PathFixDestination.backupSettings);

      final request = container.read(databaseSettingsRouteIntentProvider);
      expect(request, isNotNull);
      // Καρτέλα «Αντίγραφα ασφαλείας» — όχι η πρώτη που τυχαίνει να ανοίγει.
      expect(request!.tabIndex, 1);
      // Καμία αλλαγή οθόνης: ο διάλογος ανοίγει πάνω από τον έλεγχο, ώστε τα
      // αποτελέσματά του να μη χαθούν.
      expect(container.read(mainNavRequestProvider), isNull);
    },
  );

  testWidgets('το απομακρυσμένο εργαλείο μένει μέσα στο hub «Διάφορα»', (
    tester,
  ) async {
    final ref = await _pumpRef(tester, container);
    final before = container.read(remoteToolsViewRequestProvider);

    requestPathFixNavigation(ref, PathFixDestination.remoteTools);

    expect(container.read(remoteToolsViewRequestProvider), greaterThan(before));
    // Καμία αλλαγή οθόνης: η ρύθμιση ζει μία κάρτα παραδίπλα.
    expect(container.read(mainNavRequestProvider), isNull);
  });

  testWidgets('ο φάκελος ενημερώσεων ανοίγει τις Ρυθμίσεις στην ενότητά του', (
    tester,
  ) async {
    final ref = await _pumpRef(tester, container);

    requestPathFixNavigation(ref, PathFixDestination.updateFolder);

    expect(
      container.read(settingsRouteIntentProvider),
      SettingsSection.updates,
    );
  });

  testWidgets('οι διαδρομές λεξικού ανοίγουν και τον διάλογο ρυθμίσεων', (
    tester,
  ) async {
    final ref = await _pumpRef(tester, container);

    requestPathFixNavigation(ref, PathFixDestination.dictionaryPaths);

    final request = container.read(mainNavRequestProvider);
    expect(request, isNotNull);
    expect(request!.destination, MainNavDestination.dictionary);
    // Χωρίς αυτό ο χρήστης θα έφτανε στο Λεξικό και θα έψαχνε το ⚙ μόνος του.
    expect(request.openDictionarySettings, isTrue);
  });
}
