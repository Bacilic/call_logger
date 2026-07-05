import 'package:http/http.dart' as http;



/// Αποτέλεσμα πρότασης τίτλου/περιγραφής/λύσης για ticket.

typedef AiTicketSuggestion = ({

  String title,

  String description,

  String solution,

});



/// Εύρος αποτυχίας πρότασης ΤΝ — καθορίζει retry/fallback.

enum AiSuggestionFailureScope {

  model,

  infrastructure,

}



/// Λόγος μετάβασης σε εφεδρικό μοντέλο (για μηνύματα UI).

enum AiFallbackReason {

  modelFailure,

  rateLimited,

  overloaded,

  cooldown,

}



/// Κείμενα εισόδου για χτίσιμο προτροπής και κλήση ΤΝ.

class AiTicketSuggestionRequest {

  const AiTicketSuggestionRequest({

    required this.callerText,

    required this.equipmentText,

    required this.departmentText,

    required this.category,

    required this.issue,

    required this.titleText,

    required this.notesText,

    required this.solutionText,

  });



  final String callerText;

  final String equipmentText;

  final String departmentText;

  final String category;

  final String issue;

  final String titleText;

  final String notesText;

  final String solutionText;

}



/// Σφάλμα πρότασης ΤΝ (ρύθμιση, HTTP, μορφή απάντησης).

class AiSuggestionException implements Exception {

  const AiSuggestionException(

    this.message, {

    this.statusCode,

    this.scope,

    this.retryAvailableAt,

    this.waitingModel,

  });



  final String message;

  final int? statusCode;

  final AiSuggestionFailureScope? scope;

  final DateTime? retryAvailableAt;

  final String? waitingModel;



  @override

  String toString() => message;

}



/// Γενική διεπαφή πρότασης ticket μέσω ΤΝ (ανεξάρτητη από πάροχο).

abstract interface class AiTicketSuggestionService {

  String buildPrompt(AiTicketSuggestionRequest request);



  /// Μήνυμα σφάλματος ρύθμισης ή null όταν η διαμόρφωση είναι έγκυρη.

  String? validateConfiguration();



  Future<AiTicketSuggestion> suggest(

    AiTicketSuggestionRequest request, {

    required http.Client client,

    void Function(String model)? onModelAttempt,

    void Function(String fromModel, String toModel, AiFallbackReason reason)?

        onFallback,

  });

}

