import 'package:flutter/material.dart';

import '../../../../../core/models/floor_plan_state.dart';
import '../floor_plan_editor_controller.dart';

/// Η πλαϊνή στήλη του πατρόν: φόρτωση, βαθμονόμηση, διαφάνεια, ίσιωμα,
/// απόκρυψη, αφαίρεση.
class FloorPlanPatternPanel extends StatelessWidget {
  const FloorPlanPatternPanel({
    super.key,
    required this.controller,
    required this.onLoadFromFloorPlan,
    required this.onLoadFromFile,
  });

  final FloorPlanEditorController controller;
  final VoidCallback onLoadFromFloorPlan;
  final VoidCallback onLoadFromFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = controller.state;
    final hasImage = controller.patternImage != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Πατρόν', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Η εικόνα στο φόντο, πάνω στην οποία σχεδιάζετε. Δεν τη βλέπει '
          'κανείς άλλος.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onLoadFromFloorPlan,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Από την κάτοψη του ορόφου'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onLoadFromFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Από αρχείο εικόνας…'),
        ),
        if (hasImage) ...[
          const Divider(height: 32),
          _CalibrationStatus(state: state),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => controller.setTool(FloorPlanTool.calibrate),
            icon: const Icon(Icons.straighten),
            label: const Text('Βαθμονόμηση κλίμακας'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => controller.setTool(FloorPlanTool.movePattern),
            icon: const Icon(Icons.open_with),
            label: const Text('Μετακίνηση πατρόν'),
          ),
          const SizedBox(height: 20),
          Text('Διαφάνεια', style: theme.textTheme.labelLarge),
          Slider(
            value: state.patternOpacity,
            min: 0.1,
            max: 1,
            label: '${(state.patternOpacity * 100).round()}%',
            divisions: 18,
            onChanged: (v) =>
                controller.previewPattern(state.copyWith(patternOpacity: v)),
            onChangeEnd: (_) => controller.commitPattern(),
          ),
          const SizedBox(height: 8),
          _RotationControls(controller: controller),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Απόκρυψη πατρόν'),
            value: state.patternHidden,
            onChanged: (v) =>
                controller.updatePattern(state.copyWith(patternHidden: v)),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Αφαίρεση πατρόν'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αφαίρεση πατρόν'),
        content: const Text(
          'Η εικόνα φεύγει από το φόντο. Το σχέδιο μένει όπως είναι, και η '
          'κλίμακα κρατιέται για το επόμενο πατρόν.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Αφαίρεση'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.removePattern();
  }
}

class _CalibrationStatus extends StatelessWidget {
  const _CalibrationStatus({required this.state});

  final FloorPlanState state;

  @override
  Widget build(BuildContext context) {
    final calibrated = state.patternCalibrated;
    final color = calibrated ? Colors.green.shade700 : Colors.orange.shade800;
    return Row(
      children: [
        Icon(
          calibrated ? Icons.check_circle_outline : Icons.info_outline,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            calibrated
                ? 'Η κλίμακα έχει βαθμονομηθεί.'
                : 'Χωρίς βαθμονόμηση: τα μήκη δεν είναι ακόμη πραγματικά '
                      'μέτρα.',
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// Ίσιωμα του πατρόν: ελεύθερη κλίση και κουμπιά ανά 90°.
class _RotationControls extends StatelessWidget {
  const _RotationControls({required this.controller});

  final FloorPlanEditorController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final degrees = _normalize(state.patternRotationDegrees);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ίσιωμα: ${degrees.toStringAsFixed(1).replaceAll('.', ',')}°',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Slider(
          value: degrees,
          min: -180,
          max: 180,
          onChanged: (v) => controller.previewPattern(
            state.copyWith(patternRotationDegrees: v),
          ),
          onChangeEnd: (_) => controller.commitPattern(),
        ),
        Wrap(
          spacing: 4,
          children: [
            _step(context, '−90°', -90),
            _step(context, '−0,5°', -0.5),
            _step(context, '+0,5°', 0.5),
            _step(context, '+90°', 90),
          ],
        ),
      ],
    );
  }

  Widget _step(BuildContext context, String label, double delta) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () {
        final state = controller.state;
        controller.updatePattern(
          state.copyWith(
            patternRotationDegrees: _normalize(
              state.patternRotationDegrees + delta,
            ),
          ),
        );
      },
      child: Text(label),
    );
  }

  static double _normalize(double degrees) {
    var d = degrees % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }
}
