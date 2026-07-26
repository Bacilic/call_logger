import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/window_placement_mode.dart';
import 'settings_service.dart';

/// Εφαρμογή και αποθήκευση θέσης/μεγέθους κύριου παραθύρου (Windows).
class DesktopWindowService {
  DesktopWindowService([SettingsService? settings])
      : _settings = settings ?? SettingsService();

  final SettingsService _settings;

  /// Μετά το [show]: μέγεθος, έπειτα θέση σύμφωνα με ρύθμιση χρήστη.
  Future<void> applyStartupPlacement({
    required WindowManager windowManager,
    required double screenWidth,
    required double screenHeight,
    required double minWidth,
    required double minHeight,
  }) async {
    final savedSize = await _settings.getSavedWindowSize();
    final bounds = await windowManager.getBounds();
    final targetW = savedSize?.width ?? bounds.width;
    final targetH = savedSize?.height ?? bounds.height;
    final width = math.min(screenWidth, math.max(targetW, minWidth));
    final height = math.min(screenHeight, math.max(targetH, minHeight));

    if ((width - bounds.width).abs() > 0.5 ||
        (height - bounds.height).abs() > 0.5) {
      await windowManager.setSize(Size(width, height));
    }

    final mode = await _settings.getWindowPlacementMode();
    if (mode == WindowPlacementMode.alwaysCenter) {
      await windowManager.center();
      return;
    }

    final savedPosition = await _settings.getSavedWindowPosition();
    if (savedPosition != null) {
      final clamped = _clampPosition(
        x: savedPosition.x,
        y: savedPosition.y,
        width: width,
        height: height,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      );
      await windowManager.setPosition(Offset(clamped.x, clamped.y));
      return;
    }

    if (savedSize == null) {
      await windowManager.center();
    }
  }

  /// Αποθηκεύει τρέχον μέγεθος και (αν χρειάζεται) θέση παραθύρου.
  Future<void> persistWindowBounds(WindowManager windowManager) async {
    if (await windowManager.isMaximized()) return;
    final bounds = await windowManager.getBounds();
    await _settings.setSavedWindowSize(
      width: bounds.width,
      height: bounds.height,
    );
    final mode = await _settings.getWindowPlacementMode();
    if (mode == WindowPlacementMode.lastPosition) {
      await _settings.setSavedWindowPosition(
        x: bounds.left,
        y: bounds.top,
      );
    }
  }

  ({double x, double y}) _clampPosition({
    required double x,
    required double y,
    required double width,
    required double height,
    required double screenWidth,
    required double screenHeight,
  }) {
    final maxX = math.max(0.0, screenWidth - width);
    final maxY = math.max(0.0, screenHeight - height);
    return (
      x: x.clamp(0.0, maxX),
      y: y.clamp(0.0, maxY),
    );
  }
}
