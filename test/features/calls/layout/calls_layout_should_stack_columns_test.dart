import 'package:call_logger/core/config/calls_layout_config.dart';
import 'package:call_logger/features/calls/layout/calls_layout_plan.dart';
import 'package:call_logger/features/calls/layout/calls_layout_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callsLayoutShouldStackColumns', () {
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

    test('στοίβα όταν πλάτος < breakpoint', () {
      expect(
        callsLayoutShouldStackColumns(
          contentWidth: callsLayoutNarrowViewportBreakpoint - 1,
          plan: planWithThreeCols(),
        ),
        isTrue,
      );
    });

    test('στοίβα όταν ανά στήλη < ελάχιστο πλάτος', () {
      // 3 στήλες, 2×16 gutters → (1050-32)/3 ≈ 339 < 380
      expect(
        callsLayoutShouldStackColumns(
          contentWidth: 1050 - 32,
          plan: planWithThreeCols(),
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
  });
}
