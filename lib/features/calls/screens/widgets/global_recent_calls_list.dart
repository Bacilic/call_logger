import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_model.dart';
import '../../provider/calls_dashboard_providers.dart';

/// Διάκενο μεταξύ στήλων ώρα / τηλέφωνο / καλών.
const double _kGlobalRecentGap = 8;

/// Ελάχιστο διάκενο μεταξύ στήλης «Καλών» και «Τμήμα».
const double _kGlobalRecentDeptLeadingGap = 12;

/// Ελάχιστος χώρος που μένει για τη στήλη τμήματος (υπόλοιπο = Expanded).
const double _kGlobalRecentDeptMinReserve = 72;

String _globalRecentDisplayOrDash(String? text) {
  final value = (text ?? '').trim();
  return value.isEmpty ? '—' : value;
}

/// Ημερομηνία `calls.date` ως τοπική ημερομηνία (μόνο ημέρα), από `yyyy-MM-dd`.
DateTime? _globalRecentParseSqlDateOnly(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// Σήμερα: μόνο ώρα · Χθες: «Χθες ώρα» · άλλο: «ηη-μμ-εε ώρα» (`calls.time` / `--:--`).
String _globalRecentCallDateTimeLabel(CallModel call) {
  final t = (call.time ?? '').trim();
  final timePart = t.isEmpty ? '--:--' : t;
  final d = _globalRecentParseSqlDateOnly(call.date);
  if (d == null) return timePart;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final callDay = DateTime(d.year, d.month, d.day);
  if (callDay == today) return timePart;

  final yesterday = today.subtract(const Duration(days: 1));
  if (callDay == yesterday) return 'Χθες $timePart';

  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = (d.year % 100).toString().padLeft(2, '0');
  return '$dd-$mm-$yy $timePart';
}

double _globalRecentTextWidth(
  String text,
  TextStyle style,
  TextScaler textScaler,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout(maxWidth: double.infinity);
  return painter.size.width;
}

class _RecentCallColumnWidths {
  const _RecentCallColumnWidths({
    required this.time,
    required this.phone,
    required this.caller,
  });

  final double time;
  final double phone;
  final double caller;
}

_RecentCallColumnWidths _intrinsicRecentColumnWidths(
  BuildContext context,
  ThemeData theme,
  List<CallModel> calls,
) {
  final textScaler = MediaQuery.textScalerOf(context);
  final headerStyle = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w600,
  );
  final bodySmall = theme.textTheme.bodySmall ?? const TextStyle();
  final bodyMedium = theme.textTheme.bodyMedium ?? const TextStyle();

  var maxTime = _globalRecentTextWidth('Ώρα', headerStyle, textScaler);
  var maxPhone = _globalRecentTextWidth('Τηλέφωνο', headerStyle, textScaler);
  var maxCaller = _globalRecentTextWidth('Καλών', headerStyle, textScaler);

  for (final c in calls) {
    maxTime = math.max(
      maxTime,
      _globalRecentTextWidth(
        _globalRecentCallDateTimeLabel(c),
        bodySmall,
        textScaler,
      ),
    );
    maxPhone = math.max(
      maxPhone,
      _globalRecentTextWidth(
        _globalRecentDisplayOrDash(c.phoneText),
        bodySmall,
        textScaler,
      ),
    );
    maxCaller = math.max(
      maxCaller,
      _globalRecentTextWidth(
        _globalRecentDisplayOrDash(c.callerText),
        bodyMedium,
        textScaler,
      ),
    );
  }

  return _RecentCallColumnWidths(
    time: maxTime.ceilToDouble(),
    phone: maxPhone.ceilToDouble(),
    caller: maxCaller.ceilToDouble(),
  );
}

class GlobalRecentCallsList extends ConsumerWidget {
  const GlobalRecentCallsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isVisible = ref.watch(showGlobalCallsToggleProvider);

    final asyncCalls =
        isVisible ? ref.watch(globalRecentCallsProvider) : null;
    final measureCalls = asyncCalls?.maybeWhen(
          data: (c) => c,
          orElse: () => const <CallModel>[],
        ) ??
        const <CallModel>[];
    final intrinsic = _intrinsicRecentColumnWidths(
      context,
      theme,
      measureCalls,
    );

    Widget content;
    if (!isVisible) {
      content = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Η προβολή είναι προσωρινά κρυφή.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      content = asyncCalls!.when(
        data: (calls) {
          if (calls.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Δεν υπάρχουν πρόσφατες κλήσεις.'),
            );
          }
          return Column(
            children: [
              for (final c in calls)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = _clampedRecentWidths(
                        intrinsic,
                        constraints.maxWidth,
                      );
                      return _RecentCallDataRow(
                        theme: theme,
                        call: c,
                        widths: w,
                        displayOrDash: _globalRecentDisplayOrDash,
                      );
                    },
                  ),
                ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Αποτυχία φόρτωσης ιστορικού.'),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Τελευταίες 7 Κλήσεις',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: isVisible,
                  onChanged: (value) => ref
                      .read(showGlobalCallsToggleProvider.notifier)
                      .setVisible(value),
                ),
              ],
            ),
            if (isVisible)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = _clampedRecentWidths(
                      intrinsic,
                      constraints.maxWidth,
                    );
                    return _RecentCallHeaderRow(theme: theme, widths: w);
                  },
                ),
              ),
            content,
          ],
        ),
      ),
    );
  }
}

_RecentCallColumnWidths _clampedRecentWidths(
  _RecentCallColumnWidths intrinsic,
  double maxRowWidth,
) {
  if (!maxRowWidth.isFinite || maxRowWidth <= 0) return intrinsic;

  const floorTime = 28.0;
  const floorPhone = 32.0;
  const floorCaller = 48.0;
  final gaps = 2 * _kGlobalRecentGap + _kGlobalRecentDeptLeadingGap;
  final availableFixed =
      maxRowWidth - gaps - _kGlobalRecentDeptMinReserve;
  final sum = intrinsic.time + intrinsic.phone + intrinsic.caller;
  if (sum <= availableFixed) return intrinsic;

  var time = intrinsic.time;
  var phone = intrinsic.phone;
  var caller = intrinsic.caller;
  var deficit = sum - availableFixed;

  final fromCaller = math.min(deficit, math.max(0.0, caller - floorCaller));
  caller -= fromCaller;
  deficit -= fromCaller;

  if (deficit > 0) {
    final fromPhone = math.min(deficit, math.max(0.0, phone - floorPhone));
    phone -= fromPhone;
    deficit -= fromPhone;
  }
  if (deficit > 0) {
    time = math.max(floorTime, time - deficit);
  }

  return _RecentCallColumnWidths(time: time, phone: phone, caller: caller);
}

class _RecentCallHeaderRow extends StatelessWidget {
  const _RecentCallHeaderRow({
    required this.theme,
    required this.widths,
  });

  final ThemeData theme;
  final _RecentCallColumnWidths widths;

  @override
  Widget build(BuildContext context) {
    final h = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: widths.time,
          child: Text('Ώρα', style: h, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: _kGlobalRecentGap),
        SizedBox(
          width: widths.phone,
          child: Text('Τηλέφωνο', style: h, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: _kGlobalRecentGap),
        SizedBox(
          width: widths.caller,
          child: Text('Καλών', style: h, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: _kGlobalRecentDeptLeadingGap),
        Expanded(
          child: Text(
            'Τμήμα',
            style: h,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RecentCallDataRow extends StatelessWidget {
  const _RecentCallDataRow({
    required this.theme,
    required this.call,
    required this.widths,
    required this.displayOrDash,
  });

  final ThemeData theme;
  final CallModel call;
  final _RecentCallColumnWidths widths;
  final String Function(String?) displayOrDash;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: widths.time,
          child: Text(
            _globalRecentCallDateTimeLabel(call),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: _kGlobalRecentGap),
        SizedBox(
          width: widths.phone,
          child: Text(
            displayOrDash(call.phoneText),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: _kGlobalRecentGap),
        SizedBox(
          width: widths.caller,
          child: Text(
            displayOrDash(call.callerText),
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: _kGlobalRecentDeptLeadingGap),
        Expanded(
          child: Text(
            displayOrDash(call.departmentText),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
