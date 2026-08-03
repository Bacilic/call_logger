import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/text_layout_utils.dart';

/// Πλάτος της ζώνης εικονιδίου κάθε κουμπιού πλοήγησης.
///
/// Ταυτίζεται με το `minWidth` που χρησιμοποιεί το [NavigationRail] σε Material 3:
/// μέσα σε αυτά τα pixel κεντράρεται το εικονίδιο και αμέσως μετά ξεκινά η λεζάντα.
const double kMainNavRailIconZoneWidth = 80.0;

/// Περιθώριο που αφήνει το [NavigationRail] μετά τη λεζάντα κάθε κουμπιού.
const double kMainNavRailLabelTrailingPadding = 8.0;

/// Λίγη επιπλέον ανάσα ώστε η πιο μακριά λεζάντα να μην ακουμπά τη διαχωριστική γραμμή.
const double kMainNavRailBreathingRoom = 6.0;

/// Πλάτος της ανοιχτής πλευρικής μπάρας: όσο ακριβώς χρειάζεται η πιο μακριά
/// από τις [labels] που είναι εκείνη τη στιγμή ορατές.
///
/// Χωρίς αυτό, το [NavigationRail] κρατά το εργοστασιακό `minExtendedWidth`
/// (256 px) ανεξάρτητα από το περιεχόμενο, αφήνοντας νεκρό κενό πριν τη γραμμή.
///
/// Το αποτέλεσμα δεν πέφτει ποτέ κάτω από το φυσικό πλάτος του πιο πλατιού
/// κουμπιού· διαφορετικά τα κουμπιά θα έπαιρναν διαφορετικά πλάτη και θα
/// κεντράρονταν ένα-ένα, με τα εικονίδια να «σκορπίζουν» οριζόντια.
double mainNavRailExtendedWidth({
  required Iterable<String> labels,
  required TextStyle style,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final widestLabel = widestSingleLineTextWidth(
    texts: labels,
    style: style,
    textScaler: textScaler,
  );
  final needed =
      kMainNavRailIconZoneWidth +
      widestLabel +
      kMainNavRailLabelTrailingPadding +
      kMainNavRailBreathingRoom;
  return math.max(kMainNavRailIconZoneWidth, needed.ceilToDouble());
}
