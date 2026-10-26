import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/json.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';

/// Slim peak meter for a track or one master channel.
class PeakMeter extends StatelessWidget {
  const PeakMeter({
    super.key,
    required this.controller,
    this.trackId,
    this.width = 9,
  });

  final RemoteController controller;
  final int? trackId;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (trackId == null) {
      return ValueListenableBuilder<MeterSnapshot>(
        valueListenable: controller.meters,
        builder:
            (context, meters, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: width,
                  child: _MeterBar(reading: meters.masterLeft, width: width),
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: width,
                  child: _MeterBar(reading: meters.masterRight, width: width),
                ),
              ],
            ),
      );
    }
    return ValueListenableBuilder<MeterSnapshot>(
      valueListenable: controller.meters,
      builder:
          (context, meters, _) => SizedBox(
            width: width,
            child: _MeterBar(reading: meters.track(trackId!), width: width),
          ),
    );
  }
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({required this.reading, required this.width});

  final MeterReading reading;
  final double width;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeterPainter(reading),
        size: Size(width, double.infinity),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.reading);

  final MeterReading reading;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(outer, Paint()..color = const Color(0xFF0A0C0F));
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    final inner = Rect.fromLTWH(
      2,
      2,
      math.max(1, size.width - 4),
      math.max(1, size.height - 4),
    );
    final radius = RRect.fromRectAndRadius(inner, const Radius.circular(1.5));
    canvas.save();
    canvas.clipRRect(radius);

    final peak = meterToFader(reading.peak.clamp(0, 1).toDouble());
    final hold = meterToFader(reading.hold.clamp(0, 1).toDouble());
    final fillHeight = inner.height * peak;
    final fillRect = Rect.fromLTWH(
      inner.left,
      inner.bottom - fillHeight,
      inner.width,
      fillHeight,
    );
    if (fillHeight > 0.5) {
      final gradient = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xFF2FBF71),
          Color(0xFF57C84D),
          Color(0xFFE7C93D),
          Color(0xFFF08A2A),
          Color(0xFFFF453A),
        ],
        stops: [0, 0.48, 0.72, 0.87, 1],
      ).createShader(inner);
      canvas.drawRect(fillRect, Paint()..shader = gradient);
    }

    // Small segmentation lines help read level at a glance on glass screens.
    final segment =
        Paint()
          ..color = const Color(0x55000000)
          ..strokeWidth = 0.7;
    for (var y = inner.top + 3; y < inner.bottom; y += 5) {
      canvas.drawLine(Offset(inner.left, y), Offset(inner.right, y), segment);
    }

    if (reading.hold > 0.005) {
      final y = inner.bottom - inner.height * hold;
      canvas.drawRect(
        Rect.fromLTWH(inner.left, y, inner.width, 1.6),
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }

    if (reading.peak >= 0.995) {
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, inner.width, 3),
        Paint()..color = AppColors.danger,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) {
    return oldDelegate.reading.peak != reading.peak ||
        oldDelegate.reading.hold != reading.hold;
  }
}
