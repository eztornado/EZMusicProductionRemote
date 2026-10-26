import 'dart:math' as math;

/// Formats an absolute position as `m:ss.mmm` (or `h:mm:ss.mmm` when needed).
String formatClock(double seconds, {bool showMillis = true}) {
  final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final totalMs = (safe * 1000).round();
  final hours = totalMs ~/ 3600000;
  final minutes = (totalMs % 3600000) ~/ 60000;
  final secs = (totalMs % 60000) ~/ 1000;
  final millis = totalMs % 1000;
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write('$hours:');
    buffer.write(minutes.toString().padLeft(2, '0'));
  } else {
    buffer.write(minutes);
  }
  buffer.write(':');
  buffer.write(secs.toString().padLeft(2, '0'));
  if (showMillis) {
    buffer.write('.');
    buffer.write(millis.toString().padLeft(3, '0'));
  }
  return buffer.toString();
}

/// Formats a timeline position as `bar.beat.tick` (ticks are 0..95).
String formatBarsBeats(
  double seconds, {
  required double bpm,
  required int numerator,
  required int denominator,
}) {
  final safeBpm = bpm > 0 ? bpm : 120.0;
  final safeNum = numerator > 0 ? numerator : 4;
  final safeDen = denominator > 0 ? denominator : 4;
  final beatSeconds = 60 / safeBpm * (4 / safeDen);
  final barSeconds = beatSeconds * safeNum;
  final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final bars = (safe / barSeconds).floor();
  final inBar = safe - bars * barSeconds;
  final beat = (inBar / beatSeconds).floor();
  final inBeat = inBar - beat * beatSeconds;
  final tick = ((inBeat / beatSeconds) * 96).floor().clamp(0, 95);
  return '${bars + 1}.${beat + 1}.${tick.toString().padLeft(2, '0')}';
}

String formatDb(double gain, {String minusInfinity = '-∞ dB'}) {
  if (!gain.isFinite || gain <= 0.0001) return minusInfinity;
  final db = 20 * math.log(gain) / math.ln10;
  final rounded = db.abs() < 0.05 ? 0.0 : db;
  final sign = rounded > 0 ? '+' : '';
  return '$sign${rounded.toStringAsFixed(1)} dB';
}

/// Linear gain to decibels. Silence returns -120 so sliders can clamp safely.
double gainToDb(double gain) {
  if (!gain.isFinite || gain <= 0.0001) return -120;
  return 20 * math.log(gain) / math.ln10;
}

String formatPan(double pan) {
  final value = pan.isFinite ? pan.clamp(-1.0, 1.0) : 0.0;
  final amount = (value.abs() * 100).round();
  if (amount < 2) return 'C';
  return '${value < 0 ? 'L' : 'R'}$amount';
}

String formatSeconds(double seconds, {int decimals = 2}) {
  if (!seconds.isFinite) return '0.00 s';
  return '${seconds.toStringAsFixed(decimals)} s';
}

String formatPercent(double value, {int decimals = 0}) {
  if (!value.isFinite) return '0%';
  return '${(value * 100).toStringAsFixed(decimals)}%';
}

/// Bar length in seconds for a tempo and time signature.
double barSeconds(double bpm, int numerator, int denominator) {
  final safeBpm = bpm > 0 ? bpm : 120.0;
  final safeNum = numerator > 0 ? numerator : 4;
  final safeDen = denominator > 0 ? denominator : 4;
  return safeNum * 60 / safeBpm * (4 / safeDen);
}

double beatSeconds(double bpm, int denominator) {
  final safeBpm = bpm > 0 ? bpm : 120.0;
  final safeDen = denominator > 0 ? denominator : 4;
  return 60 / safeBpm * (4 / safeDen);
}

/// Rounds [value] to the nearest multiple of [grid]. `grid <= 0` is a no-op.
double snapTo(double value, double grid) {
  if (!grid.isFinite || grid <= 0) return value;
  return (value / grid).round() * grid;
}

String formatTrackType(String type) =>
    type == 'instrument' ? 'Instrument' : 'Audio';

String formatClipKind(String kind) => kind == 'midi' ? 'MIDI' : 'Audio';
