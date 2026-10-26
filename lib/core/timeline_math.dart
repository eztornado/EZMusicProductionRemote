import 'format.dart';

enum ClipDragMode { move, trimStart, trimEnd }

class ClipGeometry {
  const ClipGeometry({
    required this.start,
    required this.length,
    required this.offset,
  });

  final double start;
  final double length;
  final double offset;
}

/// Pure clip-drag maths, kept out of the widget so it can be tested without a
/// Flutter binding.
ClipGeometry dragClip({
  required ClipGeometry original,
  required ClipDragMode mode,
  required double deltaSeconds,
  required bool snap,
  required double gridSeconds,
  double minLength = 0.05,
}) {
  final safeGrid = snap ? gridSeconds : 0.0;
  switch (mode) {
    case ClipDragMode.move:
      final start = _snap(
        (original.start + deltaSeconds).clamp(0.0, double.infinity).toDouble(),
        safeGrid,
      );
      return ClipGeometry(
        start: start,
        length: original.length,
        offset: original.offset,
      );
    case ClipDragMode.trimStart:
      final desiredStart = _snap(
        (original.start + deltaSeconds)
            .clamp(0.0, original.start + original.length - minLength)
            .toDouble(),
        safeGrid,
      );
      var delta = desiredStart - original.start;
      final offset =
          (original.offset + delta).clamp(0.0, double.infinity).toDouble();
      delta = offset - original.offset;
      final start = original.start + delta;
      final length =
          (original.length - delta)
              .clamp(minLength, double.infinity)
              .toDouble();
      return ClipGeometry(start: start, length: length, offset: offset);
    case ClipDragMode.trimEnd:
      final desired = original.length + deltaSeconds;
      final length =
          _snap(desired, safeGrid).clamp(minLength, double.infinity).toDouble();
      return ClipGeometry(
        start: original.start,
        length: length,
        offset: original.offset,
      );
  }
}

double _snap(double value, double grid) {
  if (grid <= 0) return value;
  final snapped = snapTo(value, grid);
  return snapped < 0 ? 0 : snapped;
}

/// The grid used by the timeline: bars when zoomed far out, beats otherwise.
double timelineGridSeconds({
  required double bpm,
  required int numerator,
  required int denominator,
  required double pixelsPerSecond,
}) {
  final beat = beatSeconds(bpm, denominator);
  final bar = beat * (numerator > 0 ? numerator : 4);
  return pixelsPerSecond < 22 ? bar : beat;
}
