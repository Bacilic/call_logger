import 'package:flutter/material.dart';

/// Πόσο ψηλή είναι η κάρτα μιας κλήσης — **μετρημένη**, όχι μαντεμένη.
///
/// Η λίστα είναι εικονικοποιημένη: δίνει στον κύλινδρο το ύψος κάθε στοιχείου
/// χωρίς να το χτίσει, ώστε η μπάρα κύλισης να ξέρει από το πρώτο καρέ πόσο
/// μακρύ είναι το περιεχόμενο. Όταν τα ύψη είναι ανόμοια και μαντεμένα, το
/// σύρσιμο της μπάρας μεταπηδά — γνωστό συμπτωμα σε αυτό το έργο.
///
/// Το ίδιο αποτέλεσμα τροφοδοτεί **και** το ύψος του κειμένου μέσα στην κάρτα:
/// δύο χωριστοί υπολογισμοί θα απέκλιναν, και η απόκλιση θα εμφανιζόταν ως
/// σφάλμα διάταξης ή ως κομμένο κείμενο.
abstract final class LansweeperReportRowMetrics {
  LansweeperReportRowMetrics._();

  /// Κάθετα περιθώρια, γραμμή μεταδεδομένων και το κενό ως το κείμενο.
  ///
  /// Δεν είναι στρογγυλοποίηση: η γραμμή μεταδεδομένων περιέχει την ένδειξη
  /// κατάστασης, που είναι ψηλότερη από το κείμενο δίπλα της. Το παλιό σταθερό
  /// ύψος της κάρτας (90) με κείμενο 42 υπονοούσε ακριβώς αυτό το υπόλοιπο.
  static const double chromeHeight = 48;

  /// Επιπλέον χώρος στο τελευταίο στοιχείο κάθε ομάδας.
  static const double groupBottomHeight = 16;

  /// Πόσες γραμμές το πολύ παίρνει η Περιγραφή και πόσες η Λύση.
  static const int maxIssueLines = 2;
  static const int maxSolutionLines = 1;

  /// Το ύψος ενός κειμένου στο διαθέσιμο πλάτος, ή 0 όταν δεν υπάρχει κείμενο.
  static double textBlockHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
    required TextScaler textScaler,
  }) {
    if (text.trim().isEmpty) return 0;
    if (maxWidth <= 0) return 0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// Το συνολικό ύψος του κειμένου της κάρτας (Περιγραφή + Λύση).
  static double bodyHeight({
    required String issue,
    required String solution,
    required TextStyle style,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    return textBlockHeight(
          text: issue,
          style: style,
          maxWidth: maxWidth,
          maxLines: maxIssueLines,
          textScaler: textScaler,
        ) +
        textBlockHeight(
          text: solution,
          style: style,
          maxWidth: maxWidth,
          maxLines: maxSolutionLines,
          textScaler: textScaler,
        );
  }

  /// Το ύψος ολόκληρης της κάρτας.
  static double rowExtent({
    required double bodyHeight,
    required bool isLastInGroup,
  }) {
    return chromeHeight + bodyHeight + (isLastInGroup ? groupBottomHeight : 0);
  }
}
