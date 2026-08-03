// Unit tests: κατανομή βλαβών κατά πλήθος ή κατά διάρκεια.
//
//   flutter test test/features/history/issue_distribution_test.dart

import 'package:call_logger/features/history/models/dashboard_summary_model.dart';
import 'package:call_logger/features/history/utils/issue_distribution.dart';
import 'package:flutter_test/flutter_test.dart';

/// Τα πραγματικά δεδομένα της κάρτας: ο εκτυπωτής έχει λίγα αλλά χρονοβόρα
/// περιστατικά, το Medico πολλά και σύντομα.
final _issues = [
  const IssueStat(name: 'Medico', count: 43, sumDurationSeconds: 11760),
  const IssueStat(name: 'Εκτυπωτής', count: 11, sumDurationSeconds: 7680),
  const IssueStat(name: 'email', count: 7, sumDurationSeconds: 2997),
  const IssueStat(name: 'Word', count: 3, sumDurationSeconds: 702),
];

void main() {
  group('buildIssueDistribution', () {
    test('η όψη πλήθους ταξινομεί κατά αριθμό κλήσεων', () {
      final view = buildIssueDistribution(
        _issues,
        IssueDistributionMetric.count,
      );
      expect(
        view.rows.map((r) => r.name).toList(),
        ['Medico', 'Εκτυπωτής', 'email', 'Word'],
      );
      expect((view.rows.first.share * 100).round(), 67);
    });

    test('η όψη διάρκειας αλλάζει τα μερίδια, όχι μόνο τη σειρά', () {
      final view = buildIssueDistribution(
        _issues,
        IssueDistributionMetric.duration,
      );
      final printer = view.rows.firstWhere((r) => r.name == 'Εκτυπωτής');
      // 17% του πλήθους αλλά 33% του χρόνου — ο λόγος που υπάρχει ο επιλογέας.
      expect((printer.share * 100).round(), 33);
      expect((view.rows.first.share * 100).round(), 51);
    });

    test('η σειρά μπορεί να διαφέρει ανάμεσα στις δύο όψεις', () {
      final shortButFrequent = [
        const IssueStat(name: 'Α', count: 50, sumDurationSeconds: 1000),
        const IssueStat(name: 'Β', count: 5, sumDurationSeconds: 9000),
      ];
      expect(
        buildIssueDistribution(
          shortButFrequent,
          IssueDistributionMetric.count,
        ).rows.first.name,
        'Α',
      );
      expect(
        buildIssueDistribution(
          shortButFrequent,
          IssueDistributionMetric.duration,
        ).rows.first.name,
        'Β',
      );
    });

    test('η κάθε γραμμή κρατά και τα δύο μεγέθη, όποια όψη κι αν είναι', () {
      final view = buildIssueDistribution(
        _issues,
        IssueDistributionMetric.duration,
      );
      final medico = view.rows.firstWhere((r) => r.name == 'Medico');
      expect(medico.count, 43);
      expect(medico.durationSeconds, 11760);
    });

    test('η μπάρα της πρώτης γραμμής γεμίζει πάντα', () {
      for (final metric in IssueDistributionMetric.values) {
        final view = buildIssueDistribution(_issues, metric);
        expect(view.rows.first.barFraction, 1.0);
        expect(view.rows.last.barFraction, lessThan(1.0));
      }
    });

    test('τα σύνολα δεν εξαρτώνται από την όψη', () {
      for (final metric in IssueDistributionMetric.values) {
        final view = buildIssueDistribution(_issues, metric);
        expect(view.totalCount, 64);
        expect(view.totalDurationSeconds, 23139);
      }
    });

    test('η περικοπή δεν γίνεται σιωπηλά', () {
      final many = List<IssueStat>.generate(
        9,
        (i) => IssueStat(
          name: 'Κ$i',
          count: 10 - i,
          sumDurationSeconds: (10 - i) * 60,
        ),
      );
      final view = buildIssueDistribution(
        many,
        IssueDistributionMetric.count,
        limit: 6,
      );
      expect(view.rows.length, 6);
      expect(view.hiddenCount, 3);
      expect(view.hiddenShare, greaterThan(0));
    });

    test('χωρίς κατηγορίες επιστρέφει κενή όψη', () {
      final view = buildIssueDistribution(
        const [],
        IssueDistributionMetric.count,
      );
      expect(view.isEmpty, isTrue);
      expect(view.hiddenCount, 0);
    });

    test('μηδενικά σύνολα δεν προκαλούν διαίρεση με το μηδέν', () {
      final view = buildIssueDistribution(
        const [IssueStat(name: 'Α', count: 0, sumDurationSeconds: 0)],
        IssueDistributionMetric.duration,
      );
      expect(view.rows.single.share, 0);
      expect(view.rows.single.barFraction, 0);
    });
  });
}
