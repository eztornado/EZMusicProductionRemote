import 'dart:math' as math;

/// Parsing helpers shared by the protocol models.
///
/// The remote protocol is versioned and the server may add fields over time,
/// so every model parses defensively: missing or mistyped values fall back to a
/// safe default instead of taking the whole UI down.
double jsonDouble(Object? value, [double fallback = 0]) {
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

int jsonInt(Object? value, [int fallback = 0]) {
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

bool jsonBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase().trim();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

String jsonString(Object? value, [String fallback = '']) {
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

List<Object?> jsonList(Object? value) {
  return value is List ? value : const <Object?>[];
}

Map<String, Object?> jsonMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

/// Clamp that also survives `NaN` and infinities.
double clampDouble(num value, double min, double max) {
  if (value.isNaN) return min;
  if (value.isInfinite) return value.isNegative ? min : max;
  return value.toDouble().clamp(min, max);
}

double lerpDouble(num a, num b, double t) => a + (b - a) * t;

/// Converts a linear gain to a fader position (0..1) using a decibel scale.
double gainToFader(double gain, {double minDb = -60, double maxDb = 6}) {
  if (gain <= 0 || !gain.isFinite) return 0;
  final db = 20 * math.log(gain) / math.ln10;
  return clampDouble((db - minDb) / (maxDb - minDb), 0, 1);
}

/// Converts a fader position (0..1) to a linear gain.
double faderToGain(double position, {double minDb = -60, double maxDb = 6}) {
  final clamped = clampDouble(position, 0, 1);
  if (clamped <= 0) return 0;
  final db = minDb + (maxDb - minDb) * clamped;
  return math.pow(10, db / 20).toDouble();
}

/// Fader position for a peak meter value. Peaks are linear 0..1 but meters are
/// much easier to read on a decibel scale.
double meterToFader(double peak, {double minDb = -60, double maxDb = 6}) {
  return gainToFader(peak, minDb: minDb, maxDb: maxDb);
}

double dbToGain(double db) {
  if (db <= -120) return 0;
  return math.pow(10, db / 20).toDouble();
}
