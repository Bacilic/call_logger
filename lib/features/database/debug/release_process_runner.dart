import 'dart:convert';
import 'dart:io';

/// Εκτελεί εξωτερική εντολή (π.χ. `flutter build windows`) και προωθεί κάθε
/// γραμμή εξόδου — από `stdout` και `stderr` — στο [onOutput].
///
/// Ζει έξω από το widget: η κάρτα Δημοσίευσης δηλώνει διεπαφή, δεν στήνει
/// διεργασίες.
///
/// Δύο λεπτομέρειες που κρατούν την έξοδο ακέραιη:
/// - Ο [LineSplitter] ενώνει γραμμές που έσπασαν ανάμεσα σε δύο κομμάτια του
///   stream· η διάσπαση ανά κομμάτι θα τις εμφάνιζε κομμένες στη μέση.
/// - Η αναμονή των streams **μετά** τον κωδικό εξόδου εγγυάται ότι δεν χάνονται
///   οι τελευταίες γραμμές — αυτές που συνήθως εξηγούν την αποτυχία.
Future<int> runReleaseProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  void Function(String line)? onOutput,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: true,
  );

  Future<void> forwardLines(Stream<List<int>> stream) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (line.trim().isEmpty) return;
          onOutput?.call(line);
        });
  }

  final forwarded = Future.wait([
    forwardLines(process.stdout),
    forwardLines(process.stderr),
  ]);

  final exitCode = await process.exitCode;
  await forwarded;
  return exitCode;
}
