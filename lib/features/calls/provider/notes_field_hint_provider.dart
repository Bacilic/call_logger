import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Αυξάνεται όταν ο χρήστης πατά το ανενεργό checkbox Εκκρεμότητα·
/// το [NotesStickyField] ακούει και παίζει οπτική ένδειξη στις σημειώσεις.
final notesFieldHintTickProvider =
    NotifierProvider<NotesFieldHintNotifier, int>(NotesFieldHintNotifier.new);

class NotesFieldHintNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void requestHintFlash() => state++;
}
