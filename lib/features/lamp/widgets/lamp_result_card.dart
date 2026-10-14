import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lamp_equipment_view_model.dart';
import 'lamp_edit_section_dialog.dart';

export '../models/lamp_equipment_view_model.dart';
export 'lamp_edit_section_dialog.dart';

// Η κάρτα αποτελέσματος της Λάμπας στην οθόνη: διάταξη ανά πλάτος, ενότητες,
// αντιγραφή τιμών. Ό,τι αφορά ΤΙ δείχνει η κάρτα ζει στο μοντέλο, και η
// επεξεργασία στον δικό της διάλογο — εδώ μπαίνει μόνο εμφάνιση. Ένας
// υπολογισμός πάνω στα δεδομένα ή μια φόρμα με δική της κατάσταση δεν ανήκουν
// εδώ. Το αρχείο «δείχνει» και τα δύο, ώστε η οθόνη Λάμπας να μην αλλάζει.

const _kCardPadding = EdgeInsets.all(18);
const _kSectionSpacing = 16.0;
const _kRowSpacing = 7.0;
const _kLabelWidth = 92.0;
const _kDesktopBreakpoint = 1200.0;
const _kTabletBreakpoint = 800.0;
const _kFallbackMinWidth = 360.0;

class EquipmentResultCard extends StatefulWidget {
  const EquipmentResultCard({
    super.key,
    required this.viewModel,
    this.onSaveSection,
    this.onTransferSection,
  });

  final EquipmentViewModel viewModel;
  final SaveEquipmentSection? onSaveSection;
  final TransferSectionRequest? onTransferSection;

  @override
  State<EquipmentResultCard> createState() => _EquipmentResultCardState();
}

class _EquipmentResultCardState extends State<EquipmentResultCard> {
  final ValueNotifier<bool> _hovered = ValueNotifier(false);
  late EquipmentViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel;
  }

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EquipmentResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      _viewModel = widget.viewModel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = _viewModel.sections;

    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: _hovered,
        builder: (context, hovered, child) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: hovered ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: child,
          );
        },
        child: Padding(
          padding: _kCardPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              if (sections.isEmpty) {
                return Text(
                  'Δεν υπάρχουν διαθέσιμες πληροφορίες.',
                  style: theme.textTheme.bodyMedium,
                );
              }
              if (!maxWidth.isFinite || maxWidth < _kFallbackMinWidth) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: _kFallbackMinWidth,
                    ),
                    child: _VerticalSections(
                      sections: sections,
                      onTransferSection: widget.onTransferSection == null
                          ? null
                          : _transferSection,
                    ),
                  ),
                );
              }
              if (maxWidth >= _kDesktopBreakpoint) {
                return _DesktopSections(
                  sections: sections,
                  onEditSection: widget.onSaveSection == null
                      ? null
                      : _editSection,
                  onTransferSection: widget.onTransferSection == null
                      ? null
                      : _transferSection,
                );
              }
              if (maxWidth >= _kTabletBreakpoint) {
                return _GridSections(
                  sections: sections,
                  columns: maxWidth >= 1000 ? 3 : 2,
                  maxWidth: maxWidth,
                  onEditSection: widget.onSaveSection == null
                      ? null
                      : _editSection,
                  onTransferSection: widget.onTransferSection == null
                      ? null
                      : _transferSection,
                );
              }
              return _VerticalSections(
                sections: sections,
                onEditSection: widget.onSaveSection == null
                    ? null
                    : _editSection,
                onTransferSection: widget.onTransferSection == null
                    ? null
                    : _transferSection,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editSection(InfoSectionData section) async {
    final save = widget.onSaveSection;
    final id = section.recordId;
    if (save == null || id == null || section.editableFields.isEmpty) return;

    final updatedFields = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditSectionDialog<InfoSectionData>(
        section: section,
        onSave: (fields) =>
            save(id: id, sectionType: section.type, updatedFields: fields),
      ),
    );
    if (updatedFields == null || updatedFields.isEmpty || !mounted) return;
    setState(() {
      _viewModel = _viewModel.copyWithUpdatedFields(updatedFields);
    });
  }

  Future<void> _transferSection(InfoSectionData section) async {
    final transfer = widget.onTransferSection;
    if (transfer == null) return;
    await transfer(sectionType: section.type, sourceRow: _viewModel.sourceRow);
  }
}

class _DesktopSections extends StatelessWidget {
  const _DesktopSections({
    required this.sections,
    this.onEditSection,
    this.onTransferSection,
  });

  final List<InfoSectionData> sections;
  final ValueChanged<InfoSectionData>? onEditSection;
  final ValueChanged<InfoSectionData>? onTransferSection;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < sections.length; index++) ...[
            Flexible(
              flex: 1,
              fit: FlexFit.tight,
              child: InfoColumnSection(
                section: sections[index],
                onEdit: onEditSection,
                onTransfer: onTransferSection,
              ),
            ),
            if (index != sections.length - 1)
              const SizedBox(width: _kSectionSpacing),
          ],
        ],
      ),
    );
  }
}

class _GridSections extends StatelessWidget {
  const _GridSections({
    required this.sections,
    required this.columns,
    required this.maxWidth,
    this.onEditSection,
    this.onTransferSection,
  });

  final List<InfoSectionData> sections;
  final int columns;
  final double maxWidth;
  final ValueChanged<InfoSectionData>? onEditSection;
  final ValueChanged<InfoSectionData>? onTransferSection;

  @override
  Widget build(BuildContext context) {
    final itemWidth = (maxWidth - (_kSectionSpacing * (columns - 1))) / columns;
    return Wrap(
      spacing: _kSectionSpacing,
      runSpacing: _kSectionSpacing,
      children: [
        for (final section in sections)
          SizedBox(
            width: itemWidth,
            child: InfoColumnSection(
              section: section,
              onEdit: onEditSection,
              onTransfer: onTransferSection,
            ),
          ),
      ],
    );
  }
}

class _VerticalSections extends StatelessWidget {
  const _VerticalSections({
    required this.sections,
    this.onEditSection,
    this.onTransferSection,
  });

  final List<InfoSectionData> sections;
  final ValueChanged<InfoSectionData>? onEditSection;
  final ValueChanged<InfoSectionData>? onTransferSection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          InfoColumnSection(
            section: sections[index],
            onEdit: onEditSection,
            onTransfer: onTransferSection,
          ),
          if (index != sections.length - 1) ...[
            const SizedBox(height: _kSectionSpacing),
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: _kSectionSpacing),
          ],
        ],
      ],
    );
  }
}

class InfoColumnSection extends StatelessWidget {
  const InfoColumnSection({
    super.key,
    required this.section,
    this.onEdit,
    this.onTransfer,
  });

  final InfoSectionData section;
  final ValueChanged<InfoSectionData>? onEdit;
  final ValueChanged<InfoSectionData>? onTransfer;

  @override
  Widget build(BuildContext context) {
    final color = section.type.color;
    final theme = Theme.of(context);
    final items = section.items;
    final rows = items.map((item) => _InfoItemRow(item: item)).toList();

    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.34), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(section.type.icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.type.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: section.canEdit
                    ? 'Επεξεργασία ${section.type.title}'
                    : 'Δεν υπάρχουν επεξεργάσιμα πεδία',
                onPressed: section.canEdit && onEdit != null
                    ? () => onEdit!(section)
                    : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (onTransfer != null &&
                  (section.type == InfoSectionType.equipment ||
                      section.type == InfoSectionType.department ||
                      section.type == InfoSectionType.owner))
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Μεταφορά ${section.type.title}',
                  onPressed: () => onTransfer!(section),
                  icon: const Icon(Icons.publish_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: 32,
            height: 2,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                rows[index],
                if (index != rows.length - 1)
                  const SizedBox(height: _kRowSpacing),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoItemRow extends StatelessWidget {
  const _InfoItemRow({required this.item});

  final InfoItem item;

  @override
  Widget build(BuildContext context) {
    final field = CopyableField(
      label: item.label,
      value: item.value ?? '',
      maxLines: item.maxLines,
    );
    final note = item.note;
    if (note == null) return field;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.only(left: _kLabelWidth, right: 30),
          child: Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class CopyableField extends StatelessWidget {
  const CopyableField({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _kLabelWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          height: 28,
          child: Tooltip(
            message: 'Αντιγραφή $label',
            waitDuration: const Duration(milliseconds: 500),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _copyValue(context),
                child: Icon(
                  Icons.copy_outlined,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyValue(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final content = 'Αντιγράφηκε $label: $value';
    final message = content.length > 80
        ? '${content.substring(0, 77)}...'
        : content;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
