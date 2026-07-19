import 'package:call_logger/core/config/calls_layout_config.dart';
import 'package:call_logger/features/calls/layout/calls_layout_plan.dart';
import 'package:call_logger/features/calls/layout/calls_layout_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callsLayoutShouldStackRow / Columns', () {
    CallsLayoutPlan planWithThreeCols() => CallsLayoutPlan(
          template: CallsLayoutTemplate.a,
          rows: [
            CallsLayoutRow([
              CallsLayoutColumn.singleSlot(CallsLayoutSlot.notes),
              CallsLayoutColumn.singleSlot(CallsLayoutSlot.categoryPending),
              CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
            ]),
          ],
        );

    CallsLayoutRow templateBInfoRow() => CallsLayoutRow([
          CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
          CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
          CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerCard),
        ]);

    test('στοίβα όταν πλάτος < breakpoint', () {
      expect(
        callsLayoutShouldStackColumns(
          contentWidth: callsLayoutNarrowViewportBreakpoint - 1,
          plan: planWithThreeCols(),
        ),
        isTrue,
      );
    });

    test('template B info row: οριζόντια στο τυπικό πλάτος ~1185', () {
      // Πριν: 4 στήλες με ίσο 380 → στοίβα μέχρι ~1568.
      // Τώρα: 3 στήλες με slot mins 180+336+280+32 = 828.
      expect(
        callsLayoutShouldStackRow(
          contentWidth: 1185,
          row: templateBInfoRow(),
        ),
        isFalse,
      );
    });

    test('template B info row: στοίβα μόνο όταν δεν χωράνε τα ελάχιστα', () {
      // 180+336+280+32 = 828
      expect(
        callsLayoutShouldStackRow(
          contentWidth: 820,
          row: templateBInfoRow(),
        ),
        isTrue,
      );
    });

    test('οριζόντιο πλέγμα όταν αρκετό πλάτος ανά στήλη', () {
      expect(
        callsLayoutShouldStackColumns(
          contentWidth: 1400,
          plan: planWithThreeCols(),
        ),
        isFalse,
      );
    });

    test('μία φαρδιά γραμμή δεν στοιβάζει άλλη στενή (ανά γραμμή)', () {
      final fat = CallsLayoutRow([
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.remoteTools),
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerCard),
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.equipmentHistory),
      ]);
      final thin = CallsLayoutRow([
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.callerCard),
        CallsLayoutColumn.singleSlot(CallsLayoutSlot.map),
      ]);
      // Πάνω από breakpoint 980· 180+336+280+320+48 = 1164 — στοίβα στα 1000
      expect(
        callsLayoutShouldStackRow(contentWidth: 1000, row: fat),
        isTrue,
      );
      // 280+336+16 = 632 — οριζόντια στα 1000
      expect(
        callsLayoutShouldStackRow(contentWidth: 1000, row: thin),
        isFalse,
      );
    });
  });
}
