import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_helper.dart';
import '../database/servers_repository.dart';
import '../models/managed_server.dart';
import '../services/server_sessions/printer_rpc_policy.dart';
import '../services/server_sessions/server_printer_service.dart';
import '../services/server_sessions/server_session_service.dart';
import '../services/server_sessions/smb1_client_status.dart';
import '../services/server_sessions/server_session_models.dart';
import '../services/settings_service.dart';

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

/// Η πολιτική «RPC εκτυπωτών» σε αυτόν τον υπολογιστή.
///
/// **Με** `autoDispose`, αντίθετα από το SMB1: αυτή η ρύθμιση αλλάζει από την
/// ίδια την οθόνη και πιάνει χωρίς επανεκκίνηση, οπότε η απάντηση μπαγιατεύει
/// μέσα στην ίδια συνεδρία.
final printerRpcPolicyProvider =
    FutureProvider.autoDispose<PrinterRpcPolicyState>((ref) async {
      return PrinterRpcPolicy.current();
    });

/// Δείχνει ο διάλογος εκτυπωτών πού ενεργοποιείται η πλήρης προβολή;
///
/// Προσωπική ρύθμιση: όποιος θέλει απλώς να βλέπει τους εκτυπωτές δεν χρειάζεται
/// την υπόδειξη, και ο επόμενος χρήστης του ίδιου υπολογιστή δεν κληρονομεί την
/// απόφασή του.
final printersLimitedViewHintProvider = FutureProvider<bool>((ref) async {
  return SettingsService().windowUi.getPrintersLimitedViewHint();
});

/// Η υπηρεσία συνεδριών — χωρίς κατάσταση, ένα στιγμιότυπο αρκεί.
final serverSessionServiceProvider = Provider<ServerSessionService>((ref) {
  return const ServerSessionService();
});

/// Η υπηρεσία εκτυπωτών και επανεκκινήσεων — χωρίς κατάσταση, ένα στιγμιότυπο.
final serverPrinterServiceProvider = Provider<ServerPrinterService>((ref) {
  return const ServerPrinterService();
});
