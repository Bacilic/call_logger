// Έλεγχος ότι ο αριθμός ticket είναι ΠΑΤΗΣΙΜΟΣ σύνδεσμος μέσα στην πρόταση.
//
// Ελέγχεται η συμπεριφορά (υπάρχει recognizer στο span) και όχι ο τύπος του
// widget: ο σύνδεσμος είναι TextSpan με recognizer, γιατί μόνο έτσι ο δείκτης
// γίνεται «χεράκι» μέσα σε παράγραφο.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// True όταν κάπου στην οθόνη ο [ticketText] αποδίδεται ως πατήσιμο span.
bool ticketRendersAsTappableLink(WidgetTester tester, String ticketText) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    var tappable = false;
    rich.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == ticketText &&
          span.recognizer != null) {
        tappable = true;
        return false;
      }
      return true;
    });
    if (tappable) return true;
  }
  return false;
}
