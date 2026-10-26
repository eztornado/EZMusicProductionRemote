import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/json.dart';
import '../theme/app_theme.dart';

/// Vertical fader with a decibel scale. Values are linear gain, matching the
/// protocol (`volume` 0..2, master 0..4).
class GainFader extends StatefulWidget {
  const GainFader({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.maxGain = 2,
    this.width = 46,
    this.label,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double maxGain;
  final double width;
  final String? label;

  @override
  State<GainFader> createState() => _GainFaderState();
}

class _GainFaderState extends State<GainFader> {
  bool _dragging = false;
  double _dragNorm = 0;
  double _availableHeight = 180;

  double get _maxDb => widget.maxGain > 2.5 ? 12 : 6;

  double get _norm =>
      _dragging ? _dragNorm : gainToFader(widget.value, maxDb: _maxDb);

  void _start(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragNorm = gainToFader(widget.value, maxDb: _maxDb);
    });
  }

  void _update(DragUpdateDetails details) {
    final height = math.max(1.0, _availableHeight);
    final next = (_dragNorm - details.delta.dy / height).clamp(0.0, 1.0);
    setState(() => _dragNorm = next);
    widget.onChanged(faderToGain(next, maxDb: _maxDb));
  }

  void _end(DragEndDetails details) {
    final gain = faderToGain(_dragNorm, maxDb: _maxDb);
    setState(() => _dragging = false);
    widget.onChangeEnd(gain);
  }

  void _cancel() {
    final gain = faderToGain(_dragNorm, maxDb: _maxDb);
    setState(() => _dragging = false);
    widget.onChangeEnd(gain);
  }

  void _reset() {
    widget.onChanged(1);
    widget.onChangeEnd(1);
  }

  void _nudge(double db) {
    final current =
        widget.value <= 0 ? 0.0 : 20 * math.log(widget.value) / math.ln10;
    final target = dbToGain((current + db).clamp(-60.0, _maxDb.toDouble()));
    widget.onChanged(target);
    widget.onChangeEnd(target);
  }

  @override
  Widget build(BuildContext context) {
    final norm = _norm;
    final currentDb =
        widget.value <= 0 ? -60.0 : 20 * math.log(widget.value) / math.ln10;
    final increased = dbToGain((currentDb + 1).clamp(-60.0, _maxDb.toDouble()));
    final decreased = dbToGain((currentDb - 1).clamp(-60.0, _maxDb.toDouble()));
    return Semantics(
      slider: true,
      label: widget.label ?? 'Volume',
      value: formatDb(widget.value),
      increasedValue: formatDb(increased),
      decreasedValue: formatDb(decreased),
      onIncrease: () => _nudge(1),
      onDecrease: () => _nudge(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _end,
        onVerticalDragCancel: _cancel,
        onDoubleTap: _reset,
        child: SizedBox(
          width: widget.width,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _availableHeight = constraints.maxHeight;
              return CustomPaint(
                painter: _FaderPainter(
                  norm: norm,
                  maxDb: _maxDb,
                  dragging: _dragging,
                ),
                size: Size(widget.width, constraints.maxHeight),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FaderPainter extends CustomPainter {
  _FaderPainter({
    required this.norm,
    required this.maxDb,
    required this.dragging,
  });

  final double norm;
  final double maxDb;
  final bool dragging;

  static const _ticks = <double>[-60, -48, -36, -24, -12, -6, 0];

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    const thumbHeight = 18.0;
    final top = 10.0;
    final bottom = size.height - 10;

    final groove = Rect.fromLTWH(centerX - 3, top, 6, bottom - top);
    canvas.drawRRect(
      RRect.fromRectAndRadius(groove, const Radius.circular(3)),
      Paint()..color = const Color(0xFF0C0E12),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(groove, const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.border,
    );

    final thumbCenter = bottom - (bottom - top) * norm;
    final fillRect = Rect.fromLTRB(
      centerX - 2,
      thumbCenter,
      centerX + 2,
      bottom,
    );
    if (fillRect.height > 0) {
      canvas.drawRect(
        fillRect,
        Paint()..color = AppColors.accent.withValues(alpha: 0.55),
      );
    }

    final tickPaint =
        Paint()
          ..color = AppColors.textFaint.withValues(alpha: 0.42)
          ..strokeWidth = 1;
    for (final db in _ticks) {
      final y =
          bottom - (bottom - top) * gainToFader(dbToGain(db), maxDb: maxDb);
      final long = db == 0 || db == -60;
      canvas.drawLine(
        Offset(centerX - 14, y),
        Offset(centerX - 14 + (long ? 4 : 2), y),
        tickPaint,
      );
      canvas.drawLine(
        Offset(centerX + 10, y),
        Offset(centerX + 10 + (long ? 4 : 2), y),
        tickPaint,
      );
      if (long) {
        final label = TextPainter(
          text: TextSpan(
            text: db == 0 ? '0' : '-60',
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 7.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(centerX + 16, y - label.height / 2));
      }
    }

    // Unity line is a useful reference when mixing on a small screen.
    final unityY = bottom - (bottom - top) * gainToFader(1, maxDb: maxDb);
    canvas.drawLine(
      Offset(centerX - 22, unityY),
      Offset(centerX + 22, unityY),
      Paint()
        ..color = AppColors.textDim.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );

    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, thumbCenter),
        width: size.width - 8,
        height: thumbHeight,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      thumbRect.shift(const Offset(0, 2)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      thumbRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF343A45), Color(0xFF252A33)],
        ).createShader(thumbRect.outerRect),
    );
    canvas.drawRRect(
      thumbRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dragging ? AppColors.accent : AppColors.borderStrong,
    );
    canvas.drawLine(
      Offset(centerX - 10, thumbCenter),
      Offset(centerX + 10, thumbCenter),
      Paint()
        ..color = dragging ? AppColors.accent : AppColors.textDim
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FaderPainter oldDelegate) {
    return oldDelegate.norm != norm ||
        oldDelegate.maxDb != maxDb ||
        oldDelegate.dragging != dragging;
  }
}

/// Compact pan knob. Drag vertically for fine control, double-tap to centre.
class PanKnob extends StatefulWidget {
  const PanKnob({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.size = 44,
    this.label,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final double size;
  final String? label;

  @override
  State<PanKnob> createState() => _PanKnobState();
}

class _PanKnobState extends State<PanKnob> {
  bool _dragging = false;
  double _dragValue = 0;

  double get _value => _dragging ? _dragValue : widget.value.clamp(-1.0, 1.0);

  void _start(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _dragValue = widget.value.clamp(-1.0, 1.0);
    });
  }

  void _update(DragUpdateDetails details) {
    final next = (_dragValue - details.delta.dy / 120).clamp(-1.0, 1.0);
    setState(() => _dragValue = next);
    widget.onChanged(next);
  }

  void _end(DragEndDetails details) {
    final value = _dragValue;
    setState(() => _dragging = false);
    widget.onChangeEnd(value);
  }

  void _cancel() {
    final value = _dragValue;
    setState(() => _dragging = false);
    widget.onChangeEnd(value);
  }

  void _center() {
    widget.onChanged(0);
    widget.onChangeEnd(0);
  }

  @override
  Widget build(BuildContext context) {
    final increased = (widget.value + 0.1).clamp(-1.0, 1.0).toDouble();
    final decreased = (widget.value - 0.1).clamp(-1.0, 1.0).toDouble();
    return Semantics(
      slider: true,
      label: widget.label ?? 'Pan',
      value: formatPan(_value),
      increasedValue: formatPan(increased),
      decreasedValue: formatPan(decreased),
      onIncrease: () {
        widget.onChanged(increased);
        widget.onChangeEnd(increased);
      },
      onDecrease: () {
        widget.onChanged(decreased);
        widget.onChangeEnd(decreased);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _end,
        onVerticalDragCancel: _cancel,
        onDoubleTap: _center,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _PanPainter(value: _value, active: _dragging),
          ),
        ),
      ),
    );
  }
}

class _PanPainter extends CustomPainter {
  _PanPainter({required this.value, required this.active});

  final double value;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.panelHigh,
    );

    final norm = (value + 1) / 2;
    final centerNorm = 0.5;
    final from = norm < centerNorm ? norm : centerNorm;
    final to = norm > centerNorm ? norm : centerNorm;
    if ((to - from).abs() > 0.001) {
      canvas.drawArc(
        rect,
        start + sweep * from,
        sweep * (to - from),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.accent.withValues(alpha: 0.85),
      );
    }

    canvas.drawCircle(
      center,
      radius - 7,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF323843), Color(0xFF1B1F26)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius - 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = active ? AppColors.accent : AppColors.borderStrong,
    );

    final angle = start + sweep * norm;
    final indicatorStart = Offset(
      center.dx + math.cos(angle) * (radius - 13),
      center.dy + math.sin(angle) * (radius - 13),
    );
    final indicatorEnd = Offset(
      center.dx + math.cos(angle) * (radius - 4),
      center.dy + math.sin(angle) * (radius - 4),
    );
    canvas.drawLine(
      indicatorStart,
      indicatorEnd,
      Paint()
        ..color = active ? AppColors.accent : AppColors.text
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    // Centre detent.
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius + 1.5),
      1.1,
      Paint()..color = AppColors.textFaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PanPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.active != active;
  }
}
