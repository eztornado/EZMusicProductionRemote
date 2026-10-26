import '../core/json.dart';

/// Transport snapshot (§8.1) plus the local timestamp used to interpolate the
/// playhead between 10 Hz server updates.
class TransportState {
  const TransportState({
    required this.playing,
    required this.recording,
    required this.position,
    required this.duration,
    required this.recordStart,
    required this.metronome,
    required this.tempoBpm,
    required this.timeSigNum,
    required this.timeSigDen,
    required this.revision,
    required this.receivedAtMicros,
  });

  factory TransportState.fromJson(
    Map<String, Object?> json, {
    int receivedAtMicros = 0,
  }) {
    return TransportState(
      playing: jsonBool(json['playing']),
      recording: jsonBool(json['recording']),
      position: jsonDouble(json['position']),
      duration: jsonDouble(json['duration']),
      recordStart: jsonDouble(json['recordStart']),
      metronome: jsonBool(json['metronome']),
      tempoBpm: jsonDouble(json['tempoBpm'], 120),
      timeSigNum: jsonInt(json['timeSigNum'], 4),
      timeSigDen: jsonInt(json['timeSigDen'], 4),
      revision: jsonInt(json['revision']),
      receivedAtMicros: receivedAtMicros,
    );
  }

  static const empty = TransportState(
    playing: false,
    recording: false,
    position: 0,
    duration: 0,
    recordStart: 0,
    metronome: false,
    tempoBpm: 120,
    timeSigNum: 4,
    timeSigDen: 4,
    revision: 0,
    receivedAtMicros: 0,
  );

  final bool playing;
  final bool recording;
  final double position;
  final double duration;
  final double recordStart;
  final bool metronome;
  final double tempoBpm;
  final int timeSigNum;
  final int timeSigDen;
  final int revision;
  final int receivedAtMicros;

  bool get isRunning => playing || recording;

  TransportState copyWith({
    bool? playing,
    bool? recording,
    double? position,
    double? duration,
    double? recordStart,
    bool? metronome,
    double? tempoBpm,
    int? timeSigNum,
    int? timeSigDen,
    int? revision,
    int? receivedAtMicros,
  }) {
    return TransportState(
      playing: playing ?? this.playing,
      recording: recording ?? this.recording,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      recordStart: recordStart ?? this.recordStart,
      metronome: metronome ?? this.metronome,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      timeSigNum: timeSigNum ?? this.timeSigNum,
      timeSigDen: timeSigDen ?? this.timeSigDen,
      revision: revision ?? this.revision,
      receivedAtMicros: receivedAtMicros ?? this.receivedAtMicros,
    );
  }
}

class MeterReading {
  const MeterReading({this.peak = 0, this.hold = 0});

  final double peak; // 0..1 linear
  final double hold; // peak-hold line, 0..1

  MeterReading copyWith({double? peak, double? hold}) {
    return MeterReading(peak: peak ?? this.peak, hold: hold ?? this.hold);
  }
}

/// Smoothed track and master meters. The controller applies attack/release so
/// the UI can paint at the 20 Hz event rate without looking twitchy.
class MeterSnapshot {
  const MeterSnapshot({
    required this.tracks,
    required this.masterLeft,
    required this.masterRight,
    required this.updatedAtMicros,
  });

  static const empty = MeterSnapshot(
    tracks: <int, MeterReading>{},
    masterLeft: MeterReading(),
    masterRight: MeterReading(),
    updatedAtMicros: 0,
  );

  final Map<int, MeterReading> tracks;
  final MeterReading masterLeft;
  final MeterReading masterRight;
  final int updatedAtMicros;

  MeterReading track(int id) => tracks[id] ?? const MeterReading();
}

class ServerInfo {
  const ServerInfo({
    required this.app,
    required this.port,
    required this.requiresToken,
    required this.protocol,
    required this.projectName,
    required this.capabilities,
    required this.clientId,
  });

  factory ServerInfo.fromWelcome(Map<String, Object?> result) {
    final server = jsonMap(result['server']);
    return ServerInfo(
      app: jsonString(server['app'], 'EZMusicProduction'),
      port: jsonInt(server['port'], 47823),
      requiresToken: jsonBool(server['requiresToken'], true),
      protocol: jsonInt(server['protocol'], 1),
      projectName: jsonString(server['projectName']),
      capabilities: jsonList(server['capabilities'])
          .map((item) => jsonString(item))
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      clientId: jsonInt(result['clientId']),
    );
  }

  final String app;
  final int port;
  final bool requiresToken;
  final int protocol;
  final String projectName;
  final List<String> capabilities;
  final int clientId;
}

class DiscoveredServer {
  const DiscoveredServer({
    required this.host,
    required this.port,
    required this.app,
    required this.protocol,
    required this.requiresToken,
  });

  factory DiscoveredServer.fromDiscovery(
    Map<String, Object?> json, {
    required String host,
    required int port,
  }) {
    return DiscoveredServer(
      host: host,
      port: jsonInt(json['port'], port),
      app: jsonString(json['app'], 'EZMusicProduction'),
      protocol: jsonInt(json['protocol'], 1),
      requiresToken: jsonBool(json['requiresToken'], true),
    );
  }

  final String host;
  final int port;
  final String app;
  final int protocol;
  final bool requiresToken;

  String get id => '$host:$port';
}

class RemoteDevice {
  const RemoteDevice({
    required this.host,
    required this.port,
    required this.token,
    required this.projectName,
    required this.lastUsed,
  });

  factory RemoteDevice.fromJson(Map<String, Object?> json) {
    return RemoteDevice(
      host: jsonString(json['host']).trim().toLowerCase(),
      port: jsonInt(json['port'], 47823),
      token: jsonString(json['token']).trim(),
      projectName: jsonString(json['projectName']),
      lastUsed:
          DateTime.tryParse(jsonString(json['lastUsed'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String host;
  final int port;
  final String token;
  final String projectName;
  final DateTime lastUsed;

  String get id => '$host:$port';
  bool get hasToken => token.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'token': token,
    'projectName': projectName,
    'lastUsed': lastUsed.toIso8601String(),
  };

  RemoteDevice copyWith({
    String? host,
    int? port,
    String? token,
    String? projectName,
    DateTime? lastUsed,
  }) {
    return RemoteDevice(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      projectName: projectName ?? this.projectName,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

enum ConnectionPhase {
  idle,
  connecting,
  connected,
  reconnecting,
  authFailed,
  error,
}

class RemoteConnection {
  const RemoteConnection({
    this.phase = ConnectionPhase.idle,
    this.host,
    this.port = 47823,
    this.projectName,
    this.message,
    this.attempt = 0,
  });

  static const idle = RemoteConnection();

  final ConnectionPhase phase;
  final String? host;
  final int port;
  final String? projectName;
  final String? message;
  final int attempt;

  bool get isConnected => phase == ConnectionPhase.connected;
  bool get isBusy =>
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.reconnecting;
  bool get hasSession => host != null;
  String? get endpoint => host == null ? null : '$host:$port';

  RemoteConnection copyWith({
    ConnectionPhase? phase,
    String? host,
    int? port,
    String? projectName,
    String? message,
    int? attempt,
  }) {
    return RemoteConnection(
      phase: phase ?? this.phase,
      host: host ?? this.host,
      port: port ?? this.port,
      projectName: projectName ?? this.projectName,
      message: message,
      attempt: attempt ?? this.attempt,
    );
  }
}

class PluginInfo {
  const PluginInfo({
    required this.index,
    required this.name,
    required this.isInstrument,
    required this.format,
  });

  factory PluginInfo.fromJson(Map<String, Object?> json) {
    return PluginInfo(
      index: jsonInt(json['index']),
      name: jsonString(json['name'], 'Plugin'),
      isInstrument: jsonBool(json['isInstrument']),
      format: jsonString(json['format']),
    );
  }

  final int index;
  final String name;
  final bool isInstrument;
  final String format;
}

class FxParam {
  const FxParam({
    required this.index,
    required this.name,
    required this.value,
    required this.text,
  });

  factory FxParam.fromJson(Map<String, Object?> json) {
    return FxParam(
      index: jsonInt(json['index']),
      name: jsonString(json['name'], 'Parameter'),
      value: clampDouble(jsonDouble(json['value']), 0, 1),
      text: jsonString(json['text']),
    );
  }

  final int index;
  final String name;
  final double value; // normalized 0..1
  final String text;

  FxParam copyWith({double? value, String? text}) {
    return FxParam(
      index: index,
      name: name,
      value: value ?? this.value,
      text: text ?? this.text,
    );
  }
}

class RemoteApiException implements Exception {
  const RemoteApiException(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  bool get isAuthError => code == 'auth_failed' || code == 'auth_required';
  bool get isConnectionError =>
      code == 'socket' || code == 'not_connected' || code == 'timeout';

  @override
  String toString() => 'RemoteApiException($code: $message)';
}

class UiError {
  const UiError({required this.message, this.code, this.sequence = 0});

  final String message;
  final String? code;
  final int sequence;
}
