import 'package:flutter/material.dart';

enum DashboardPalette { classic, ocean, sunrise, forest, indigoNight }

class KpiTone {
  const KpiTone({
    required this.surface,
    required this.iconSurface,
    required this.iconColor,
    required this.valueColor,
    required this.sparkColor,
  });

  final Color surface;
  final Color iconSurface;
  final Color iconColor;
  final Color valueColor;
  final Color sparkColor;
}

class DashboardPaletteColors {
  const DashboardPaletteColors({
    required this.kpiBlue,
    required this.kpiGreen,
    required this.kpiOrange,
    required this.kpiPurple,
    required this.actionBlue,
    required this.pageBg,
    required this.pageGradientStart,
    required this.pageGradientEnd,
    required this.glassFill,
    required this.glassBorder,
    required this.topBarFill,
    required this.topBarBorder,
    required this.topBarLogoBgStart,
    required this.topBarLogoBgEnd,
    required this.topBarLogoIcon,
    required this.kpiTitle,
    required this.kpiSubtitle,
    required this.rankSwatches,
    required this.sectionCallersIcon,
    required this.sectionCallersBg,
    required this.sectionDurationIcon,
    required this.sectionDurationBg,
    required this.tableHeaderBg,
    required this.tableRowHover,
    required this.progressTrackBg,
    required this.progressTrackDataRowBg,
    required this.pieColors,
    required this.chartCardFill,
    required this.chartCardBorder,
    required this.chartGridLine,
  });

  final KpiTone kpiBlue;
  final KpiTone kpiGreen;
  final KpiTone kpiOrange;
  final KpiTone kpiPurple;
  final Color actionBlue;
  final Color pageBg;
  final Color pageGradientStart;
  final Color pageGradientEnd;
  final Color glassFill;
  final Color glassBorder;
  final Color topBarFill;
  final Color topBarBorder;
  final Color topBarLogoBgStart;
  final Color topBarLogoBgEnd;
  final Color topBarLogoIcon;
  final Color kpiTitle;
  final Color kpiSubtitle;
  final List<Color> rankSwatches;
  final Color sectionCallersIcon;
  final Color sectionCallersBg;
  final Color sectionDurationIcon;
  final Color sectionDurationBg;
  final Color tableHeaderBg;
  final Color tableRowHover;
  final Color progressTrackBg;
  final Color progressTrackDataRowBg;
  final List<Color> pieColors;
  final Color chartCardFill;
  final Color chartCardBorder;
  final Color chartGridLine;

  Color rankColor(int index) =>
      rankSwatches[index % rankSwatches.length];

  factory DashboardPaletteColors.from(DashboardPalette palette) {
    switch (palette) {
      case DashboardPalette.classic:
        return const DashboardPaletteColors(
          kpiBlue: KpiTone(
            surface: Color(0xFFEEF6FF),
            iconSurface: Color(0xFFDBEAFE),
            iconColor: Color(0xFF2563EB),
            valueColor: Color(0xFF0B63CE),
            sparkColor: Color(0xFF3B82F6),
          ),
          kpiGreen: KpiTone(
            surface: Color(0xFFE9F9F1),
            iconSurface: Color(0xFFD1FAE5),
            iconColor: Color(0xFF059669),
            valueColor: Color(0xFF047857),
            sparkColor: Color(0xFF10B981),
          ),
          kpiOrange: KpiTone(
            surface: Color(0xFFFFF4E8),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
            valueColor: Color(0xFFC2410C),
            sparkColor: Color(0xFFF97316),
          ),
          kpiPurple: KpiTone(
            surface: Color(0xFFF5F0FF),
            iconSurface: Color(0xFFEDE9FE),
            iconColor: Color(0xFF7C3AED),
            valueColor: Color(0xFF6D28D9),
            sparkColor: Color(0xFF8B5CF6),
          ),
          actionBlue: Color(0xFF2563EB),
          pageBg: Color(0xFFEFF3FC),
          pageGradientStart: Color(0xFFEAF2FF),
          pageGradientEnd: Color(0xFFF7FAFF),
          glassFill: Color(0xFFF4F8FF),
          glassBorder: Color(0xFFE2EAF6),
          topBarFill: Color(0xFFFFFFFF),
          topBarBorder: Color(0xFFE8EEF7),
          topBarLogoBgStart: Color(0xFFF0F6FF),
          topBarLogoBgEnd: Color(0xFFE2EDFF),
          topBarLogoIcon: Color(0xFF2563EB),
          kpiTitle: Color(0xFF334155),
          kpiSubtitle: Color(0xFF64748B),
          rankSwatches: [
            Color(0xFFE0F2FE),
            Color(0xFFDCFCE7),
            Color(0xFFFFEDD5),
            Color(0xFFEDE9FE),
            Color(0xFFFCE7F3),
            Color(0xFFE0F2FE),
            Color(0xFFDCFCE7),
          ],
          sectionCallersIcon: Color(0xFFD97706),
          sectionCallersBg: Color(0xFFFFF4D6),
          sectionDurationIcon: Color(0xFF1D4ED8),
          sectionDurationBg: Color(0xFFDBEAFE),
          tableHeaderBg: Color(0xFFF8FAFD),
          tableRowHover: Color(0xFFF1F6FF),
          progressTrackBg: Color(0xFFE6EBF7),
          progressTrackDataRowBg: Color(0xFFE5EDFF),
          pieColors: [
            Color(0xFF3B82F6),
            Color(0xFF10B981),
            Color(0xFFF59E0B),
            Color(0xFFA855F7),
            Color(0xFFEF4444),
          ],
          chartCardFill: Color(0xFFFFFFFF),
          chartCardBorder: Color(0xFFE2E8F0),
          chartGridLine: Color(0xFFE5EAF6),
        );
      case DashboardPalette.ocean:
        return const DashboardPaletteColors(
          kpiBlue: KpiTone(
            surface: Color(0xFFEFF8FF),
            iconSurface: Color(0xFFD8EEFF),
            iconColor: Color(0xFF0284C7),
            valueColor: Color(0xFF0369A1),
            sparkColor: Color(0xFF0EA5E9),
          ),
          kpiGreen: KpiTone(
            surface: Color(0xFFEDFBF7),
            iconSurface: Color(0xFFD2F6EC),
            iconColor: Color(0xFF0D9488),
            valueColor: Color(0xFF0F766E),
            sparkColor: Color(0xFF14B8A6),
          ),
          kpiOrange: KpiTone(
            surface: Color(0xFFFFF7ED),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFEA580C),
            valueColor: Color(0xFFC2410C),
            sparkColor: Color(0xFFF97316),
          ),
          kpiPurple: KpiTone(
            surface: Color(0xFFF4F4FF),
            iconSurface: Color(0xFFE9E8FF),
            iconColor: Color(0xFF6366F1),
            valueColor: Color(0xFF4F46E5),
            sparkColor: Color(0xFF6366F1),
          ),
          actionBlue: Color(0xFF0284C7),
          pageBg: Color(0xFFE8F5FB),
          pageGradientStart: Color(0xFFDCF0FA),
          pageGradientEnd: Color(0xFFF3FBFE),
          glassFill: Color(0xFFF2FAFD),
          glassBorder: Color(0xFFCDE8F4),
          topBarFill: Color(0xFFF8FCFE),
          topBarBorder: Color(0xFFD6EEF7),
          topBarLogoBgStart: Color(0xFFE0F7FF),
          topBarLogoBgEnd: Color(0xFFC8EFFF),
          topBarLogoIcon: Color(0xFF0284C7),
          kpiTitle: Color(0xFF1E3A4A),
          kpiSubtitle: Color(0xFF4A7390),
          rankSwatches: [
            Color(0xFFE0F7FA),
            Color(0xFFB2EBF2),
            Color(0xFFCCFBF1),
            Color(0xFFE0F2FE),
            Color(0xFFDBEAFE),
            Color(0xFFE0F7FA),
            Color(0xFFB2EBF2),
          ],
          sectionCallersIcon: Color(0xFF0D9488),
          sectionCallersBg: Color(0xFFCCFBF1),
          sectionDurationIcon: Color(0xFF0369A1),
          sectionDurationBg: Color(0xFFE0F2FE),
          tableHeaderBg: Color(0xFFECF8FC),
          tableRowHover: Color(0xFFE4F6FB),
          progressTrackBg: Color(0xFFD4EBF5),
          progressTrackDataRowBg: Color(0xFFCFE4F7),
          pieColors: [
            Color(0xFF0EA5E9),
            Color(0xFF14B8A6),
            Color(0xFFF59E0B),
            Color(0xFF6366F1),
            Color(0xFFF43F5E),
          ],
          chartCardFill: Color(0xFFF8FDFF),
          chartCardBorder: Color(0xFFC7E2EE),
          chartGridLine: Color(0xFFDAEAF4),
        );
      case DashboardPalette.sunrise:
        return const DashboardPaletteColors(
          kpiBlue: KpiTone(
            surface: Color(0xFFF1F7FF),
            iconSurface: Color(0xFFDDEBFF),
            iconColor: Color(0xFF2563EB),
            valueColor: Color(0xFF1E40AF),
            sparkColor: Color(0xFF3B82F6),
          ),
          kpiGreen: KpiTone(
            surface: Color(0xFFF4FDF4),
            iconSurface: Color(0xFFDCFCE7),
            iconColor: Color(0xFF16A34A),
            valueColor: Color(0xFF166534),
            sparkColor: Color(0xFF22C55E),
          ),
          kpiOrange: KpiTone(
            surface: Color(0xFFFFF6EC),
            iconSurface: Color(0xFFFFEDD5),
            iconColor: Color(0xFFF97316),
            valueColor: Color(0xFFEA580C),
            sparkColor: Color(0xFFF59E0B),
          ),
          kpiPurple: KpiTone(
            surface: Color(0xFFFFF0FA),
            iconSurface: Color(0xFFFCE7F3),
            iconColor: Color(0xFFDB2777),
            valueColor: Color(0xFFBE185D),
            sparkColor: Color(0xFFEC4899),
          ),
          actionBlue: Color(0xFF1D4ED8),
          pageBg: Color(0xFFFFF7F2),
          pageGradientStart: Color(0xFFFFEDE5),
          pageGradientEnd: Color(0xFFFFFAF6),
          glassFill: Color(0xFFFFFCF9),
          glassBorder: Color(0xFFF5E0D6),
          topBarFill: Color(0xFFFFFFFF),
          topBarBorder: Color(0xFFF8E8E0),
          topBarLogoBgStart: Color(0xFFFFE8EF),
          topBarLogoBgEnd: Color(0xFFFFD6E5),
          topBarLogoIcon: Color(0xFFBE185D),
          kpiTitle: Color(0xFF422B2B),
          kpiSubtitle: Color(0xFF7C6560),
          rankSwatches: [
            Color(0xFFFFE4E6),
            Color(0xFFFFE7D5),
            Color(0xFFE0F2FE),
            Color(0xFFFCE7F3),
            Color(0xFFFEF3C7),
            Color(0xFFFFE4E6),
            Color(0xFFFFE7D5),
          ],
          sectionCallersIcon: Color(0xFFC2410C),
          sectionCallersBg: Color(0xFFFFEDD5),
          sectionDurationIcon: Color(0xFFBE185D),
          sectionDurationBg: Color(0xFFFCE7F3),
          tableHeaderBg: Color(0xFFFFF5F0),
          tableRowHover: Color(0xFFFFEDE5),
          progressTrackBg: Color(0xFFF5E6DE),
          progressTrackDataRowBg: Color(0xFFF5E1F0),
          pieColors: [
            Color(0xFF1D4ED8),
            Color(0xFFEC4899),
            Color(0xFFF59E0B),
            Color(0xFF22C55E),
            Color(0xFFA855F7),
          ],
          chartCardFill: Color(0xFFFFFFFF),
          chartCardBorder: Color(0xFFF0D9CE),
          chartGridLine: Color(0xFFF5E6DD),
        );
      case DashboardPalette.forest:
        return const DashboardPaletteColors(
          kpiBlue: KpiTone(
            surface: Color(0xFFE8F1FF),
            iconSurface: Color(0xFFD4E4FF),
            iconColor: Color(0xFF1D4ED8),
            valueColor: Color(0xFF1E3A8A),
            sparkColor: Color(0xFF2563EB),
          ),
          kpiGreen: KpiTone(
            surface: Color(0xFFDFF7EC),
            iconSurface: Color(0xFFB7F0D1),
            iconColor: Color(0xFF047857),
            valueColor: Color(0xFF065F46),
            sparkColor: Color(0xFF10B981),
          ),
          kpiOrange: KpiTone(
            surface: Color(0xFFFFF4E6),
            iconSurface: Color(0xFFFFE8CC),
            iconColor: Color(0xFFC2410C),
            valueColor: Color(0xFF9A3412),
            sparkColor: Color(0xFFEA580C),
          ),
          kpiPurple: KpiTone(
            surface: Color(0xFFF3E8FF),
            iconSurface: Color(0xFFE9D5FF),
            iconColor: Color(0xFF6D28D9),
            valueColor: Color(0xFF5B21B6),
            sparkColor: Color(0xFF9333EA),
          ),
          actionBlue: Color(0xFF047857),
          pageBg: Color(0xFFECF8F1),
          pageGradientStart: Color(0xFFE0F4E8),
          pageGradientEnd: Color(0xFFF4FBF6),
          glassFill: Color(0xFFF6FCF8),
          glassBorder: Color(0xFFC9E8D8),
          topBarFill: Color(0xFFF7FDF9),
          topBarBorder: Color(0xFFD1EADD),
          topBarLogoBgStart: Color(0xFFD1FAE5),
          topBarLogoBgEnd: Color(0xFFA7F3D0),
          topBarLogoIcon: Color(0xFF047857),
          kpiTitle: Color(0xFF1C2D26),
          kpiSubtitle: Color(0xFF4A6356),
          rankSwatches: [
            Color(0xFFD1FAE5),
            Color(0xFFE0F2FE),
            Color(0xFFFEF9C3),
            Color(0xFFE9D5FF),
            Color(0xFFFFE4E6),
            Color(0xFFDCFCE7),
            Color(0xFFCCFBF1),
          ],
          sectionCallersIcon: Color(0xFFB45309),
          sectionCallersBg: Color(0xFFFEF3C7),
          sectionDurationIcon: Color(0xFF047857),
          sectionDurationBg: Color(0xFFD1FAE5),
          tableHeaderBg: Color(0xFFEAF6EF),
          tableRowHover: Color(0xFFE0F0E6),
          progressTrackBg: Color(0xFFD5E8DD),
          progressTrackDataRowBg: Color(0xFFC9E2D4),
          pieColors: [
            Color(0xFF059669),
            Color(0xFF0D9488),
            Color(0xFFCA8A04),
            Color(0xFF7C3AED),
            Color(0xFFDC2626),
          ],
          chartCardFill: Color(0xFFF6FBF8),
          chartCardBorder: Color(0xFFC5DCCC),
          chartGridLine: Color(0xFFD6E8DD),
        );
      case DashboardPalette.indigoNight:
        return const DashboardPaletteColors(
          kpiBlue: KpiTone(
            surface: Color(0xFFEAEEFC),
            iconSurface: Color(0xFFD8DDFA),
            iconColor: Color(0xFF4338CA),
            valueColor: Color(0xFF3730A3),
            sparkColor: Color(0xFF4F46E5),
          ),
          kpiGreen: KpiTone(
            surface: Color(0xFFECFDF5),
            iconSurface: Color(0xFFD1FAE5),
            iconColor: Color(0xFF059669),
            valueColor: Color(0xFF047857),
            sparkColor: Color(0xFF10B981),
          ),
          kpiOrange: KpiTone(
            surface: Color(0xFFFFF5F1),
            iconSurface: Color(0xFFFFE4D6),
            iconColor: Color(0xFFEA580C),
            valueColor: Color(0xFFC2410C),
            sparkColor: Color(0xFFF97316),
          ),
          kpiPurple: KpiTone(
            surface: Color(0xFFF5F2FF),
            iconSurface: Color(0xFFEDE9FE),
            iconColor: Color(0xFF7C3AED),
            valueColor: Color(0xFF6D28D9),
            sparkColor: Color(0xFF8B5CF6),
          ),
          actionBlue: Color(0xFF4338CA),
          pageBg: Color(0xFFEDEDFA),
          pageGradientStart: Color(0xFFE4E4F7),
          pageGradientEnd: Color(0xFFF6F6FF),
          glassFill: Color(0xFFF7F7FF),
          glassBorder: Color(0xFFD8D8EE),
          topBarFill: Color(0xFFF9F9FF),
          topBarBorder: Color(0xFFE0E0F4),
          topBarLogoBgStart: Color(0xFFE0E7FF),
          topBarLogoBgEnd: Color(0xFFC7D2FE),
          topBarLogoIcon: Color(0xFF4338CA),
          kpiTitle: Color(0xFF1E1B4B),
          kpiSubtitle: Color(0xFF575569),
          rankSwatches: [
            Color(0xFFE0E7FF),
            Color(0xFFDCFCE7),
            Color(0xFFFFE4E6),
            Color(0xFFE9D5FF),
            Color(0xFFFEF3C7),
            Color(0xFFEDE9FE),
            Color(0xFFDBEAFE),
          ],
          sectionCallersIcon: Color(0xFFC2410C),
          sectionCallersBg: Color(0xFFFFEDD5),
          sectionDurationIcon: Color(0xFF4338CA),
          sectionDurationBg: Color(0xFFE0E7FF),
          tableHeaderBg: Color(0xFFEEEEFF),
          tableRowHover: Color(0xFFE4E4F9),
          progressTrackBg: Color(0xFFDADBF0),
          progressTrackDataRowBg: Color(0xFFD8DAF2),
          pieColors: [
            Color(0xFF4F46E5),
            Color(0xFF10B981),
            Color(0xFFF97316),
            Color(0xFFA855F7),
            Color(0xFFEF4444),
          ],
          chartCardFill: Color(0xFFFAFAFF),
          chartCardBorder: Color(0xFFD4D4EA),
          chartGridLine: Color(0xFFDADAE8),
        );
    }
  }
}
