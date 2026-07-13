// Unit tests: runner-up tooltips KPI καρτών dashboard με αριθμό κατάταξης.
//
//   flutter test test/features/history/dashboard_summary_runnerup_tooltip_test.dart

import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runnerUpPointsFromDepartmentStats', () {
    test('tooltips ξεκινούν με αριθμό κατάταξης 2ο, 3ο κ.ο.κ.', () {
      const stats = [
        DepartmentStat(name: 'Κορυφαίο', count: 20, sumDurationSeconds: 0),
        DepartmentStat(name: 'Πληροφορική', count: 13, sumDurationSeconds: 0),
        DepartmentStat(name: 'Ιατρική', count: 8, sumDurationSeconds: 0),
        DepartmentStat(name: 'Οικονομικό', count: 5, sumDurationSeconds: 0),
      ];

      final points = runnerUpPointsFromDepartmentStats(stats, 5);

      expect(points[0].tooltip, '2ο · Πληροφορική: 13 κλήσεις');
      expect(points[1].tooltip, '3ο · Ιατρική: 8 κλήσεις');
      expect(points[2].tooltip, '4ο · Οικονομικό: 5 κλήσεις');
    });
  });
}
