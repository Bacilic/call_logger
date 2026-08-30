import 'package:flutter/material.dart';

import '../../../core/widgets/deleted_catalog_entity_text.dart';
import '../../../core/widgets/linkable_selectable_text.dart';
import '../models/task.dart';

/// Η αριστερή στήλη της κάρτας: τι είναι η εκκρεμότητα.
///
/// Τίτλος, περιγραφή και οι οντότητες που την αφορούν — τρία πράγματα που
/// διαβάζονται μαζί και αλλάζουν μαζί. Ό,τι αφορά **ενέργειες** ζει στην άλλη
/// στήλη· εδώ δεν πατιέται τίποτα.
class TaskCardSummary extends StatelessWidget {
  const TaskCardSummary({required this.task, super.key});

  final Task task;

  /// Η περιγραφή που πραγματικά δείχνεται: στη γρήγορη καταχώρηση το ωμό
  /// κείμενο κουβαλά και τις υποδείξεις κανόνων, που αποδίδονται χωριστά.
  String? get _description =>
      task.isQuickAdd ? task.cleanDescription : task.description;

  bool get _hasDescription => _description?.isNotEmpty == true;

  static bool _nonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;

  bool get _hasEntityMetadata =>
      _nonEmpty(task.userText) ||
      _nonEmpty(task.phoneText) ||
      _nonEmpty(task.departmentText) ||
      _nonEmpty(task.equipmentText);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          task.displayTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_hasDescription) TaskCardDescription(description: _description!),
        if (_hasDescription && _hasEntityMetadata) const SizedBox(height: 8),
        _buildEntityMetadata(theme),
      ],
    );
  }

  Widget _buildEntityMetadata(ThemeData theme) {
    final user = task.userText?.trim();
    final phone = task.phoneText?.trim();
    final dept = task.departmentText?.trim();
    final equip = task.equipmentText?.trim();

    final hasUser = user != null && user.isNotEmpty;
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasDept = dept != null && dept.isNotEmpty;
    final hasEquip = equip != null && equip.isNotEmpty;

    if (!hasUser && !hasPhone && !hasDept && !hasEquip) {
      return const SizedBox.shrink();
    }

    final onVar = theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodySmall?.copyWith(color: onVar);

    Widget row(IconData icon, String text, {bool linkedDeleted = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: onVar),
          const SizedBox(width: 4),
          Flexible(
            child: DeletedCatalogEntityText(
              text: text,
              isDeleted: linkedDeleted,
              style: textStyle,
              maxLines: 2,
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12.0,
      runSpacing: 4.0,
      children: [
        if (hasUser)
          row(
            Icons.person_outline,
            user,
            linkedDeleted: task.callerLinkedDeleted,
          ),
        if (hasPhone) row(Icons.phone_outlined, phone),
        if (hasDept)
          row(Icons.domain, dept, linkedDeleted: task.departmentLinkedDeleted),
        if (hasEquip)
          row(
            Icons.computer_outlined,
            equip,
            linkedDeleted: task.equipmentLinkedDeleted,
          ),
      ],
    );
  }
}

/// Περιγραφή εκκρεμότητας: δυναμικό ύψος έως 5 γραμμές, πάνω από 5 → κυλιώμενο πλαίσιο.
///
/// Οι γραμμές με υποδείξεις κανόνων επικύρωσης (γρήγορη καταχώρηση) φεύγουν
/// από το ελεύθερο κείμενο και αποδίδονται χωριστά, πορτοκαλί — δεν είναι
/// περιγραφή του χρήστη αλλά σημείωση προς έλεγχο.
class TaskCardDescription extends StatelessWidget {
  const TaskCardDescription({required this.description, super.key});

  static const int _maxLines = 5;

  final String description;

  /// Το κείμενο χωρίς το τμήμα υποδείξεων.
  String get _plainText {
    final marker = Task.validationHintPrefix.trim();
    return description
        .split('\n')
        .where(
          (line) =>
              !line.trimLeft().startsWith(marker) &&
              line.trim() != Task.validationHintHeader,
        )
        .join('\n')
        .trim();
  }

  List<String> get _hintLines {
    final marker = Task.validationHintPrefix.trim();
    return description
        .split('\n')
        .where((line) => line.trimLeft().startsWith(marker))
        .map((line) => line.trimLeft().replaceFirst(marker, '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final hints = _hintLines;
    final plain = _plainText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plain.isNotEmpty) _buildScrollableText(plain, style),
        if (hints.isNotEmpty) ...[
          if (plain.isNotEmpty) const SizedBox(height: 8),
          _ValidationHintBlock(hints: hints),
        ],
      ],
    );
  }

  Widget _buildScrollableText(String text, TextStyle style) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: null,
          textDirection: textDirection,
        );
        try {
          painter.layout(maxWidth: constraints.maxWidth);
          final lineHeight = painter.preferredLineHeight;
          final lineCount = (painter.height / lineHeight).ceil();
          if (lineCount <= _maxLines) {
            return LinkableSelectableText(text: text, style: style);
          }
          return SizedBox(
            height: lineHeight * _maxLines,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: LinkableSelectableText(text: text, style: style),
            ),
          );
        } finally {
          painter.dispose();
        }
      },
    );
  }
}

/// Οι υποδείξεις κανόνων μιας γρήγορης καταχώρησης — προειδοποίηση προς
/// έλεγχο, όχι σφάλμα: ίδιο πορτοκαλί με τις υποδείξεις των φορμών.
class _ValidationHintBlock extends StatelessWidget {
  const _ValidationHintBlock({required this.hints});

  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Colors.orange.shade800;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Task.validationHintHeader,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        for (final hint in hints)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
