// Πλάτος πλευρικής μπάρας: υπολογισμός από την πιο μακριά ορατή λεζάντα.
//
//   flutter test test/core/widgets/main_nav_rail_metrics_test.dart

import 'package:call_logger/core/utils/text_layout_utils.dart';
import 'package:call_logger/core/widgets/main_nav_destination.dart';
import 'package:call_logger/core/widgets/main_nav_rail_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 12);

void main() {
  group('widestSingleLineTextWidth', () {
    test('επιστρέφει το πλάτος της πιο μακριάς εγγραφής', () {
      final widest = widestSingleLineTextWidth(
        texts: const ['Λάμπα', 'Βάση Δεδομένων', 'Λεξικό'],
        style: _style,
      );
      final longest = singleLineTextWidth(
        text: 'Βάση Δεδομένων',
        style: _style,
      );

      expect(widest, longest);
    });

    test('κενό σύνολο δίνει μηδέν', () {
      expect(
        widestSingleLineTextWidth(texts: const [], style: _style),
        0,
      );
    });

    test('η κλίμακα γραμματοσειράς μεγαλώνει τη μέτρηση', () {
      final normal = widestSingleLineTextWidth(
        texts: const ['Βάση Δεδομένων'],
        style: _style,
      );
      final scaled = widestSingleLineTextWidth(
        texts: const ['Βάση Δεδομένων'],
        style: _style,
        textScaler: const TextScaler.linear(1.5),
      );

      expect(scaled, greaterThan(normal));
    });
  });

  group('mainNavRailExtendedWidth', () {
    List<String> labelsOf(List<MainNavDestination> destinations) => [
      for (final d in destinations) d.label,
      kMainNavSettingsLabel,
    ];

    const allVisible = [
      MainNavDestination.calls,
      MainNavDestination.tasks,
      MainNavDestination.directory,
      MainNavDestination.history,
      MainNavDestination.lamp,
      MainNavDestination.database,
      MainNavDestination.dictionary,
    ];

    test('χωράει την πιο μακριά λεζάντα με ελάχιστη ανάσα', () {
      final width = mainNavRailExtendedWidth(
        labels: labelsOf(allVisible),
        style: _style,
      );
      final longest = singleLineTextWidth(
        text: MainNavDestination.database.label,
        style: _style,
      );

      final gapAfterLabel = width - (kMainNavRailIconZoneWidth + longest);
      expect(gapAfterLabel, greaterThan(0));
      expect(
        gapAfterLabel,
        lessThanOrEqualTo(
          kMainNavRailLabelTrailingPadding + kMainNavRailBreathingRoom + 1,
        ),
      );
    });

    test('στενεύει όταν κρύβονται κουμπιά με μεγάλες λεζάντες', () {
      final wide = mainNavRailExtendedWidth(
        labels: labelsOf(allVisible),
        style: _style,
      );
      final narrow = mainNavRailExtendedWidth(
        labels: labelsOf(const [
          MainNavDestination.calls,
          MainNavDestination.tasks,
          MainNavDestination.directory,
          MainNavDestination.history,
        ]),
        style: _style,
      );

      expect(narrow, lessThan(wide));
    });

    test('φαρδαίνει με μεγαλύτερη κλίμακα γραμματοσειράς', () {
      final normal = mainNavRailExtendedWidth(
        labels: labelsOf(allVisible),
        style: _style,
      );
      final scaled = mainNavRailExtendedWidth(
        labels: labelsOf(allVisible),
        style: _style,
        textScaler: const TextScaler.linear(1.5),
      );

      expect(scaled, greaterThan(normal));
    });

    test('ποτέ στενότερο από τη ζώνη εικονιδίου', () {
      expect(
        mainNavRailExtendedWidth(labels: const [], style: _style),
        greaterThanOrEqualTo(kMainNavRailIconZoneWidth),
      );
    });
  });
}
