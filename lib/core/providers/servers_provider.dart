import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../database/servers_repository.dart';
import '../models/managed_server.dart';
import '../services/server_sessions/server_printer_service.dart';
import '../services/server_sessions/server_session_service.dart';
import '../services/server_sessions/smb1_client_status.dart';
import '../services/server_sessions/server_session_models.dart';

/// Πρόσβαση στον πίνακα `servers`.
final serversRepositoryProvider = Provider<ServersRepository>((ref) {
  return ServersRepository(DatabaseHelper.instance);
});

/// Οι καταχωρημένοι διακομιστές. Ακυρώνεται μετά από κάθε αλλαγή στην οθόνη.
final serversListProvider = FutureProvider<List<ManagedServer>>((ref) async {
  return ref.read(serversRepositoryProvider).getAll();
});

/// Κατάσταση SMB1 σε αυτόν τον υπολογιστή.
///
/// Χωρίς `autoDispose`: η απάντηση δεν αλλάζει παρά μόνο με επανεκκίνηση του
/// υπολογιστή, οπότε δεν υπάρχει λόγος να ξαναρωτηθεί σε κάθε άνοιγμα οθόνης.
final smb1ClientStatusProvider = FutureProvider<Smb1ClientStatus>((ref) async {
  return Smb1ClientCheck.current();
});

/// Η υπηρεσία συνεδριών — χωρίς κατάσταση, ένα στιγμιότυπο αρκεί.
final serverSessionServiceProvider = Provider<ServerSessionService>((ref) {
  return const ServerSessionService();
});

/// Η υπηρεσία εκτυπωτών και επανεκκινήσεων — χωρίς κατάσταση, ένα στιγμιότυπο.
final serverPrinterServiceProvider = Provider<ServerPrinterService>((ref) {
  return const ServerPrinterService();
});
