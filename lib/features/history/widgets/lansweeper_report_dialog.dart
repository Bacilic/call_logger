import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/models/call_model.dart';
import '../providers/dashboard_provider.dart';

class LansweeperReportDialog extends ConsumerStatefulWidget {
  const LansweeperReportDialog({super.key});

  @override
  ConsumerState<LansweeperReportDialog> createState() =>
      _LansweeperReportDialogState();
}

class _LansweeperReportDialogState extends ConsumerState<LansweeperReportDialog> {
  final Set<String> _selectedKeys = <String>{};

  String _callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? '-' : value;
  }

  String _notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    final solution = (call.solution ?? '').trim();
    if (issue.isNotEmpty && solution.isNotEmpty) return '$issue — $solution';
    if (issue.isNotEmpty) return issue;
    if (solution.isNotEmpty) return solution;
    return '-';
  }

  String _durationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _totalDurationLabel(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final totalMinutes = (safe / 60).ceil();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '$hours ώρ ${mins.toString().padLeft(2, '0')} λ';
    }
    return '$totalMinutes λ';
  }

  DateTime _callDateTime(CallModel call) {
    final dateRaw = (call.date ?? '').trim();
    final timeRaw = (call.time ?? '').trim();
    final parsed = DateTime.tryParse('$dateRaw $timeRaw');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_ReportCallItem> _toItems(List<CallModel> calls) {
    return calls.indexed.map((entry) {
      final i = entry.$1;
      final call = entry.$2;
      final id = call.id;
      final key = id != null ? 'id_$id' : 'idx_$i';
      return _ReportCallItem(
        key: key,
        call: call,
        caller: _callerLabel(call),
        notes: _notes(call),
        durationSeconds: call.duration ?? 0,
      );
    }).toList();
  }

  Map<String, List<_ReportCallItem>> _groupByCaller(List<_ReportCallItem> items) {
    final grouped = <String, List<_ReportCallItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.caller, () => <_ReportCallItem>[]).add(item);
    }
    return grouped;
  }

  bool? _groupCheckedValue(List<_ReportCallItem> items) {
    if (items.isEmpty) return false;
    final selectedCount = items.where((e) => _selectedKeys.contains(e.key)).length;
    if (selectedCount == 0) return false;
    if (selectedCount == items.length) return true;
    return null;
  }

  void _toggleGroup(List<_ReportCallItem> items, bool? checked) {
    setState(() {
      if (checked == true) {
        for (final item in items) {
          _selectedKeys.add(item.key);
        }
      } else {
        for (final item in items) {
          _selectedKeys.remove(item.key);
        }
      }
    });
  }

  void _toggleItem(_ReportCallItem item, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedKeys.add(item.key);
      } else {
        _selectedKeys.remove(item.key);
      }
    });
  }

  Future<void> _copyAndOpen({
    required List<_ReportCallItem> allItems,
    required String lansweeperUrl,
  }) async {
    final selected = allItems.where((e) => _selectedKeys.contains(e.key)).toList();
    if (selected.isEmpty) return;

    final lines = selected
        .map((e) => '${e.caller}: ${e.notes} [${_durationLabel(e.durationSeconds)}]')
        .toList();
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Αντιγράφηκαν οι επιλεγμένες κλήσεις.')),
    );

    final uri = Uri.tryParse(lansweeperUrl.trim());
    if (uri == null || !uri.hasScheme) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Μη έγκυρο Lansweeper URL.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Αποτυχία ανοίγματος Lansweeper URL.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final callsAsync = ref.watch(dashboardCallsForReportProvider);
    final lansweeperUrl = ref.watch(lansweeperUrlProvider);

    return AlertDialog(
      title: const Text('Αναφορά Lansweeper'),
      content: SizedBox(
        width: 900,
        height: 560,
        child: callsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Σφάλμα φόρτωσης κλήσεων: $e')),
          data: (calls) {
            final items = _toItems(calls);
            final grouped = _groupByCaller(items);
            final selected = items.where((e) => _selectedKeys.contains(e.key)).toList();
            final totalSelectedSeconds = selected.fold<int>(
              0,
              (sum, item) => sum + item.durationSeconds,
            );

            if (items.isEmpty) {
              return const Center(
                child: Text('Δεν βρέθηκαν κλήσεις για τα τρέχοντα φίλτρα.'),
              );
            }

            return Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Επιλεγμένες: ${selected.length} | Σύνολο διάρκειας: ${_totalDurationLabel(totalSelectedSeconds)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: grouped.entries.map((entry) {
                      final caller = entry.key;
                      final callerItems = entry.value;
                      final groupSeconds = callerItems.fold<int>(
                        0,
                        (sum, item) => sum + item.durationSeconds,
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CheckboxListTile(
                                tristate: true,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                value: _groupCheckedValue(callerItems),
                                onChanged: (v) => _toggleGroup(callerItems, v),
                                title: Text(
                                  caller,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${callerItems.length} κλήσεις • ${_totalDurationLabel(groupSeconds)}',
                                ),
                              ),
                              const Divider(height: 8),
                              ...callerItems.map((item) {
                                final date = DateFormat(
                                  'dd/MM/yyyy HH:mm',
                                ).format(_callDateTime(item.call));
                                return CheckboxListTile(
                                  dense: true,
                                  value: _selectedKeys.contains(item.key),
                                  onChanged: (v) => _toggleItem(item, v),
                                  title: Text('$date • ${_durationLabel(item.durationSeconds)}'),
                                  subtitle: Text(
                                    item.notes,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Κλείσιμο'),
        ),
        callsAsync.maybeWhen(
          data: (calls) {
            final items = _toItems(calls);
            final hasSelection = items.any((e) => _selectedKeys.contains(e.key));
            return FilledButton.icon(
              onPressed: hasSelection
                  ? () => _copyAndOpen(
                        allItems: items,
                        lansweeperUrl: lansweeperUrl,
                      )
                  : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Αντιγραφή & Άνοιγμα Lansweeper'),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ReportCallItem {
  const _ReportCallItem({
    required this.key,
    required this.call,
    required this.caller,
    required this.notes,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String caller;
  final String notes;
  final int durationSeconds;
}
