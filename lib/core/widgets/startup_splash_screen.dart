import 'dart:async';

import 'package:flutter/material.dart';

import '../init/startup_journal.dart';
import '../init/startup_splash_artwork.dart';

/// Πόσο μένει τουλάχιστον στην οθόνη η εκκίνηση.
///
/// Ελάχιστη διάρκεια, όχι σταθερή: αν οι εργασίες κρατήσουν περισσότερο, η
/// οθόνη μένει όσο χρειάζεται. Το φρένο υπάρχει για την αντίστροφη περίπτωση —
/// μια εκκίνηση που τελειώνει σε μισό δευτερόλεπτο θα άφηνε τον χρήστη να δει
/// μόνο ένα τρεμόπαιγμα.
const Duration kSplashMinimumDuration = Duration(milliseconds: 2500);

/// Πόσο μένει κάθε γραμμή πριν αποκαλυφθεί η επόμενη.
const Duration kSplashLineInterval = Duration(milliseconds: 110);

/// Η οθόνη εκκίνησης: η εικόνα της ημέρας και τα βήματα που κυλούν από κάτω
/// προς τα πάνω, σβήνοντας στο μέσο της εικόνας.
class StartupSplashScreen extends StatefulWidget {
  const StartupSplashScreen({
    super.key,
    required this.appVersion,
    required this.initializationComplete,
    required this.onFinished,
    this.artworkPicker = const SplashArtworkPicker(),
    this.minimumDuration = kSplashMinimumDuration,
    this.lineInterval = kSplashLineInterval,
  });

  /// Ετικέτα έκδοσης κάτω από το όνομα της εφαρμογής.
  final String appVersion;

  /// True μόλις η αρχικοποίηση τελειώσει επιτυχώς.
  final bool initializationComplete;

  /// Καλείται όταν η οθόνη έχει πει όσα είχε να πει και μπορεί να φύγει.
  final VoidCallback onFinished;

  final SplashArtworkPicker artworkPicker;
  final Duration minimumDuration;
  final Duration lineInterval;

  @override
  State<StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<StartupSplashScreen> {
  SplashArtwork? _artwork;
  Timer? _pacer;
  int _revealed = 0;
  bool _finished = false;

  /// Πόσα χτυπήματα του ρυθμιστή πέρασαν.
  ///
  /// Ο χρόνος μετριέται σε χτυπήματα και όχι με ρολόι τοίχου επίτηδες: ο
  /// ρυθμιστής είναι ήδη η καρδιά αυτής της οθόνης, και δύο πηγές χρόνου θα
  /// απέκλιναν — ορατά στα τεστ, όπου ο χρόνος του πλαισίου προχωρά χωρίς να
  /// κουνηθεί το ρολόι του συστήματος.
  int _ticks = 0;

  Duration get _elapsed => widget.lineInterval * _ticks;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
    _pacer = Timer.periodic(widget.lineInterval, (_) => _tick());
    StartupJournal.instance.steps.addListener(_onJournalChanged);
  }

  @override
  void dispose() {
    _pacer?.cancel();
    StartupJournal.instance.steps.removeListener(_onJournalChanged);
    super.dispose();
  }

  void _onJournalChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadArtwork() async {
    final artwork = await widget.artworkPicker.pick();
    final warning = artwork.warning;
    if (warning != null) {
      StartupJournal.instance.note(
        'Η εικόνα εκκίνησης δεν φορτώθηκε',
        status: StartupStepStatus.warning,
        detail: warning,
      );
    }
    if (mounted) setState(() => _artwork = artwork);
  }

  /// Αποκαλύπτει την επόμενη γραμμή και ελέγχει αν ήρθε η ώρα να φύγουμε.
  void _tick() {
    if (_finished || !mounted) return;
    _ticks++;
    final total = StartupJournal.instance.visibleSteps.length;

    if (_revealed < total) {
      setState(() => _revealed++);
      return;
    }

    if (!widget.initializationComplete) return;
    if (_elapsed < widget.minimumDuration) return;

    _finished = true;
    _pacer?.cancel();
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final steps = StartupJournal.instance.visibleSteps;
    final shown = steps.take(_revealed).toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFF15101F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _SplashBackground(artwork: _artwork),
          const _ReadabilityVeil(),
          Align(
            alignment: const Alignment(-0.94, -0.62),
            child: _SplashBrand(appVersion: widget.appVersion),
          ),
          Align(
            alignment: const Alignment(-0.94, 1),
            child: FractionallySizedBox(
              widthFactor: 0.44,
              heightFactor: 0.48,
              child: _StartupJournalView(steps: shown),
            ),
          ),
        ],
      ),
    );
  }
}

/// Η εικόνα, ή η χρωματική εναλλαγή όταν εικόνα δεν υπάρχει.
class _SplashBackground extends StatelessWidget {
  const _SplashBackground({required this.artwork});

  final SplashArtwork? artwork;

  @override
  Widget build(BuildContext context) {
    final current = artwork;
    if (current == null) return const SizedBox.shrink();

    if (current.isImage) {
      return Image.asset(
        current.assetPath!,
        fit: BoxFit.cover,
        // Μια εικόνα που δεν αποκωδικοποιείται δεν ρίχνει την εκκίνηση: η
        // εφεδρεία μπαίνει στη θέση της και η εφαρμογή ανοίγει κανονικά.
        errorBuilder: (_, _, _) =>
            const _GradientBackground(colors: kSplashFallbackGradients),
      );
    }
    return _GradientBackground(colors: [current.gradientColors!]);
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground({required this.colors});

  /// Μία ή περισσότερες παλέτες· χρησιμοποιείται πάντα η πρώτη.
  final List<List<Color>> colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors.first,
        ),
      ),
    );
  }
}

/// Σκοτεινιάζει την κάτω αριστερή γωνία ώστε τα γράμματα να διαβάζονται πάνω
/// σε οποιαδήποτε εικόνα, όσο φωτεινή κι αν είναι.
class _ReadabilityVeil extends StatelessWidget {
  const _ReadabilityVeil();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.96, 1),
          radius: 1.25,
          colors: [Color(0xD90A0612), Color(0xB80A0612), Color(0x000A0612)],
          stops: [0, 0.34, 0.68],
        ),
      ),
    );
  }
}

class _SplashBrand extends StatelessWidget {
  const _SplashBrand({required this.appVersion});

  final String appVersion;

  @override
  Widget build(BuildContext context) {
    const shadows = <Shadow>[
      Shadow(color: Color(0xCC000000), blurRadius: 12, offset: Offset(0, 2)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/call_logger.ico',
          width: 52,
          height: 52,
          errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Καταγραφή Κλήσεων',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w600,
                shadows: shadows,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'έκδοση $appVersion',
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 12,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Τα βήματα, στοιβαγμένα από κάτω προς τα πάνω, να σβήνουν στην κορυφή.
class _StartupJournalView extends StatelessWidget {
  const _StartupJournalView({required this.steps});

  final List<StartupStep> steps;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0x4D000000), Color(0xFF000000)],
        stops: [0, 0.36, 0.64],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomLeft,
          maxHeight: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final step in steps) _StartupStepLine(step: step),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupStepLine extends StatelessWidget {
  const _StartupStepLine({required this.step});

  final StartupStep step;

  @override
  Widget build(BuildContext context) {
    final running = step.status == StartupStepStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 16, child: _StepIcon(status: step.status)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              step.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _colorFor(step.status),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: running ? FontWeight.w600 : FontWeight.w400,
                shadows: const [
                  Shadow(color: Color(0xD9000000), blurRadius: 6),
                  Shadow(color: Color(0x80000000), blurRadius: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(StartupStepStatus status) => switch (status) {
    StartupStepStatus.running => Colors.white,
    StartupStepStatus.ok => const Color(0xB8FFFFFF),
    StartupStepStatus.skipped => const Color(0x75FFFFFF),
    StartupStepStatus.warning => const Color(0xFFFFD8A8),
    StartupStepStatus.failed => const Color(0xFFFFB4AB),
  };
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.status});

  final StartupStepStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == StartupStepStatus.running) {
      return const SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    return Icon(
      switch (status) {
        StartupStepStatus.ok => Icons.check,
        StartupStepStatus.warning => Icons.priority_high,
        StartupStepStatus.failed => Icons.close,
        _ => Icons.remove,
      },
      size: 13,
      color: _StartupStepLine._colorFor(status),
      shadows: const [Shadow(color: Color(0xD9000000), blurRadius: 6)],
    );
  }
}
