import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/json.dart';
import '../data/remote_api.dart';
import '../data/settings_store.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../models/session.dart';

/// Owns the live session: connection lifecycle, protocol state, optimistic
/// mixer updates, meters and the current selection.
///
/// UI code listens to the narrow [ValueNotifier]s instead of rebuilding the
/// whole app on every 20 Hz meter frame.
class RemoteController {
  RemoteController({
    required RemoteApiFactory apiFactory,
    required SettingsStore settingsStore,
    required AppSettings settings,
    int Function()? nowMicros,
  }) : _apiFactory = apiFactory,
       _settingsStore = settingsStore,
       _now = nowMicros ?? (() => DateTime.now().microsecondsSinceEpoch) {
    preferences = ValueNotifier<AppSettings>(settings);
  }

  final RemoteApiFactory _apiFactory;
  final SettingsStore _settingsStore;
  final int Function() _now;

  late final ValueNotifier<AppSettings> preferences;
  final ValueNotifier<RemoteConnection> connection =
      ValueNotifier<RemoteConnection>(RemoteConnection.idle);
  final ValueNotifier<RemoteProject?> project = ValueNotifier<RemoteProject?>(
    null,
  );
  final ValueNotifier<TransportState> transport = ValueNotifier<TransportState>(
    TransportState.empty,
  );
  final ValueNotifier<MeterSnapshot> meters = ValueNotifier<MeterSnapshot>(
    MeterSnapshot.empty,
  );
  final ValueNotifier<ServerInfo?> server = ValueNotifier<ServerInfo?>(null);
  final ValueNotifier<int?> selectedTrackId = ValueNotifier<int?>(null);
  final ValueNotifier<int?> selectedClipId = ValueNotifier<int?>(null);
  final ValueNotifier<List<PluginInfo>?> plugins =
      ValueNotifier<List<PluginInfo>?>(null);
  final ValueNotifier<UiError?> error = ValueNotifier<UiError?>(null);

  RemoteApi? _api;
  StreamSubscription<RemoteEvent>? _subscription;
  int _generation = 0;
  bool _connecting = false;
  bool _closedDuringConnect = false;
  bool _manualDisconnect = true;
  bool _disposed = false;

  String? _host;
  int _port = 47823;
  String? _token;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _mixTimer;
  Timer? _masterMixTimer;
  Timer? _overrideTimer;
  Timer? _refreshTimer;
  bool _refreshing = false;
  bool _refreshQueued = false;
  int _refreshToken = 0;
  int _errorSequence = 0;

  final Map<int, _TrackOverride> _trackOverrides = <int, _TrackOverride>{};
  final Map<int, Map<String, double>> _pendingMix =
      <int, Map<String, double>>{};
  double? _pendingMaster;
  _MasterOverride? _masterOverride;

  int _lastMeterMicros = 0;

  // ---------------------------------------------------------------------------
  // Public state helpers
  // ---------------------------------------------------------------------------

  AppSettings get settings => preferences.value;
  String get clientName => settings.clientName;
  RemoteProject? get currentProject => project.value;
  RemoteTrack? get selectedTrack =>
      project.value?.trackById(selectedTrackId.value);
  RemoteClip? get selectedClip => project.value?.clipById(selectedClipId.value);
  bool get hasSession => connection.value.isConnected;

  int get nowMicros => _now();

  /// Interpolates between the 10 Hz transport events so the playhead moves at
  /// display refresh rate.
  double get estimatedPosition {
    final state = transport.value;
    var position = state.position;
    if (state.isRunning && state.receivedAtMicros > 0) {
      position += (_now() - state.receivedAtMicros) / 1000000.0;
    }
    final end =
        state.duration > 0 ? state.duration : (project.value?.duration ?? 0);
    if (end > 0) position = position.clamp(0, end).toDouble();
    if (position < 0) position = 0;
    return position;
  }

  RemoteTrack? trackById(int? id) => project.value?.trackById(id);
  RemoteClip? clipById(int? id) => project.value?.clipById(id);

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  Future<bool> pair({
    required String host,
    required int port,
    required String token,
    bool remember = true,
  }) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      _fail('errorNoToken');
      return false;
    }
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _host = host.trim().toLowerCase();
    _port = port;
    _token = normalizedToken;
    await _teardownSession();
    project.value = null;
    server.value = null;
    transport.value = TransportState.empty;
    meters.value = MeterSnapshot.empty;
    plugins.value = null;
    selectedTrackId.value = null;
    selectedClipId.value = null;
    _setConnection(
      RemoteConnection(
        phase: ConnectionPhase.connecting,
        host: _host,
        port: port,
        message: null,
      ),
    );
    return _openSession(remember: remember);
  }

  /// Restores the last paired studio on launch when auto-connect is enabled.
  Future<bool> restoreLastSession() async {
    final device = settings.lastDevice;
    if (!settings.autoReconnect || device == null || !device.hasToken) {
      return false;
    }
    return pair(
      host: device.host,
      port: device.port,
      token: device.token,
      remember: false,
    );
  }

  Future<bool> _openSession({required bool remember}) async {
    final host = _host;
    final token = _token;
    if (host == null || token == null) return false;

    _connecting = true;
    _closedDuringConnect = false;
    final api = _apiFactory();
    final generation = ++_generation;
    _api = api;
    _subscription = api.events.listen(
      (event) => _onEvent(event, generation),
      onError: (Object error) {
        if (generation == _generation) _onTransportFailure(error);
      },
    );

    try {
      await api.connect(host, _port);
      final result = jsonMap(
        await api.request('hello', <String, Object?>{
          'token': token,
          'client': <String, Object?>{'name': settings.clientName},
        }),
      );
      if (_disposed || generation != _generation) {
        await api.close();
        return false;
      }
      if (_closedDuringConnect || !api.isOpen) {
        throw const RemoteApiException(
          'socket',
          'The connection closed during the handshake',
        );
      }

      final info = ServerInfo.fromWelcome(result);
      final nextProject = RemoteProject.fromJson(jsonMap(result['state']));
      final nextTransport = TransportState.fromJson(
        jsonMap(result['transport']),
        receivedAtMicros: _now(),
      );
      _clearOptimisticState();
      server.value = info;
      project.value = nextProject;
      transport.value = nextTransport;
      meters.value = MeterSnapshot.empty;
      _lastMeterMicros = 0;
      plugins.value = null;
      _ensureSelection(selectFirst: true);
      _connecting = false;
      _reconnectAttempt = 0;
      _setConnection(
        RemoteConnection(
          phase: ConnectionPhase.connected,
          host: host,
          port: _port,
          projectName: nextProject.name,
        ),
      );
      unawaited(
        api
            .request('subscribe', <String, Object?>{
              'meters': true,
              'metersHz': 20,
            })
            .catchError((Object _) => null),
      );
      if (remember) {
        _rememberDevice(
          host: host,
          port: _port,
          token: token,
          projectName: nextProject.name,
        );
      }
      return true;
    } on Object catch (raw) {
      if (generation != _generation || _disposed) {
        await api.close();
        return false;
      }
      final failure = _asApiException(raw);
      _connecting = false;
      _clearOptimisticState();
      final subscription = _subscription;
      _subscription = null;
      await subscription?.cancel();
      _api = null;
      await api.close();
      if (failure.isAuthError) {
        _setConnection(
          RemoteConnection(
            phase: ConnectionPhase.authFailed,
            host: host,
            port: _port,
            message: failure.message,
          ),
        );
        _forgetSavedToken(host, _port);
      } else {
        _setConnection(
          RemoteConnection(
            phase: ConnectionPhase.error,
            host: host,
            port: _port,
            message: failure.message,
          ),
        );
      }
      return false;
    }
  }

  void _onEvent(RemoteEvent event, int generation) {
    if (generation != _generation || _disposed) return;
    switch (event) {
      case ProjectEvent(:final project):
        final previous = this.project.value;
        this.project.value = _applyOverrides(project);
        if (previous?.name != project.name) {
          final current = connection.value;
          if (current.isConnected) {
            _setConnection(
              current.copyWith(
                projectName: project.name,
                phase: ConnectionPhase.connected,
                message: null,
              ),
            );
          }
        }
        _ensureSelection();
      case TransportEvent(:final transport):
        this.transport.value = transport;
      case MetersEvent(
        :final trackPeaks,
        :final masterLeft,
        :final masterRight,
      ):
        _applyMeters(trackPeaks, masterLeft, masterRight);
      case ConnectionClosedEvent(:final message):
        _onConnectionClosed(generation, message);
    }
  }

  void _onConnectionClosed(int generation, String? message) {
    if (generation != _generation || _manualDisconnect) return;
    if (_connecting) {
      // Do not let a close that races with `hello` turn into a fake
      // "connected" session. `_openSession` checks this flag after the
      // handshake and reports the failure through its normal error path.
      _closedDuringConnect = true;
      return;
    }
    if (_api == null) return;
    _api = null;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    _clearOptimisticState();
    connection.value = connection.value.copyWith(
      phase: ConnectionPhase.reconnecting,
      message: message,
    );
    _scheduleReconnect();
  }

  void _onTransportFailure(Object raw) {
    if (_connecting || _manualDisconnect) return;
    final failure = _asApiException(raw);
    _report(failure);
    _api = null;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    _clearOptimisticState();
    connection.value = connection.value.copyWith(
      phase: ConnectionPhase.reconnecting,
      message: failure.message,
    );
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect || !settings.autoReconnect) {
      final current = connection.value;
      if (current.phase == ConnectionPhase.reconnecting) {
        _setConnection(
          current.copyWith(
            phase: ConnectionPhase.error,
            message: current.message,
          ),
        );
      }
      return;
    }
    if (_host == null || _token == null) return;
    _reconnectTimer?.cancel();
    _reconnectAttempt++;
    final delaySeconds =
        <int>[1, 2, 3, 5, 8, 12, 20][math.min(_reconnectAttempt - 1, 6)];
    _setConnection(
      RemoteConnection(
        phase: ConnectionPhase.reconnecting,
        host: _host,
        port: _port,
        projectName: project.value?.name,
        attempt: _reconnectAttempt,
      ),
    );
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      unawaited(_attemptReconnect());
    });
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    if (_host == null || _token == null) return;
    _manualDisconnect = false;
    _reconnectAttempt++;
    _setConnection(
      RemoteConnection(
        phase: ConnectionPhase.reconnecting,
        host: _host,
        port: _port,
        projectName: project.value?.name,
        attempt: _reconnectAttempt,
      ),
    );
    await _attemptReconnect();
  }

  Future<void> _attemptReconnect() async {
    if (_disposed || _manualDisconnect) return;
    final ok = await _openSession(remember: false);
    if (!ok &&
        !_disposed &&
        !_manualDisconnect &&
        connection.value.phase == ConnectionPhase.error) {
      _scheduleReconnect();
    }
  }

  Future<void> disconnect({bool forget = false}) async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    final host = _host;
    final port = _port;
    await _teardownSession();
    _token = null;
    _host = null;
    _reconnectAttempt = 0;
    if (forget && host != null) {
      final device = settings.deviceFor(host, port);
      if (device != null) {
        _updateSettings(settings.withoutDevice(device.id));
      }
    }
    project.value = null;
    server.value = null;
    transport.value = TransportState.empty;
    meters.value = MeterSnapshot.empty;
    plugins.value = null;
    selectedTrackId.value = null;
    selectedClipId.value = null;
    _trackOverrides.clear();
    _pendingMix.clear();
    _masterOverride = null;
    _setConnection(RemoteConnection.idle);
  }

  Future<void> forgetDevice(RemoteDevice device) async {
    _updateSettings(settings.withoutDevice(device.id));
    if (_host == device.host && _port == device.port) {
      await disconnect();
    }
  }

  Future<void> _teardownSession() async {
    _generation++;
    _connecting = false;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final api = _api;
    _api = null;
    if (api != null) await api.close();
    _clearOptimisticState();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _lastMeterMicros = 0;
  }

  /// Drops previews and pending coalesced mixer values.
  ///
  /// A socket can disappear in the middle of a fader drag. Those optimistic
  /// values must never leak into the next session, and their timers must not
  /// fire against the replacement socket.
  void _clearOptimisticState() {
    _mixTimer?.cancel();
    _mixTimer = null;
    _masterMixTimer?.cancel();
    _masterMixTimer = null;
    _overrideTimer?.cancel();
    _overrideTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshing = false;
    _refreshQueued = false;
    _refreshToken++;
    _pendingMix.clear();
    _pendingMaster = null;
    _trackOverrides.clear();
    _masterOverride = null;
  }

  void _rememberDevice({
    required String host,
    required int port,
    required String token,
    required String projectName,
  }) {
    final device = RemoteDevice(
      host: host,
      port: port,
      token: token,
      projectName: projectName,
      lastUsed: DateTime.now(),
    );
    _updateSettings(settings.withDevice(device));
  }

  void _forgetSavedToken(String host, int port) {
    final device = settings.deviceFor(host, port);
    if (device != null) {
      _updateSettings(settings.withoutDevice(device.id));
    }
  }

  void _setConnection(RemoteConnection next) {
    final current = connection.value;
    if (current.phase == next.phase &&
        current.host == next.host &&
        current.port == next.port &&
        current.projectName == next.projectName &&
        current.message == next.message &&
        current.attempt == next.attempt) {
      return;
    }
    connection.value = next;
  }

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  Future<void> setLanguage(AppLanguage language) async {
    _updateSettings(settings.copyWith(language: language));
  }

  Future<void> setAutoReconnect(bool enabled) async {
    _updateSettings(settings.copyWith(autoReconnect: enabled));
    if (!enabled) {
      _reconnectTimer?.cancel();
      final current = connection.value;
      if (current.phase == ConnectionPhase.reconnecting) {
        _setConnection(
          current.copyWith(
            phase: ConnectionPhase.error,
            message: current.message,
          ),
        );
      }
    }
  }

  Future<void> setClientName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _updateSettings(settings.copyWith(clientName: trimmed));
  }

  void _updateSettings(AppSettings next) {
    preferences.value = next;
    unawaited(_settingsStore.save(next));
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<void> togglePlay() async {
    if (transport.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    try {
      await _request('transport.play');
      _setTransport(
        transport.value.copyWith(playing: true, receivedAtMicros: _now()),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> pause() async {
    try {
      await _request('transport.pause');
      _setTransport(
        transport.value.copyWith(
          playing: false,
          position: estimatedPosition,
          receivedAtMicros: _now(),
        ),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> stop() async {
    try {
      await _request('transport.stop');
      _setTransport(
        transport.value.copyWith(
          playing: false,
          recording: false,
          position: 0,
          receivedAtMicros: _now(),
        ),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> seek(double seconds) async {
    final target = math.max(0.0, seconds);
    _setTransport(
      transport.value.copyWith(position: target, receivedAtMicros: _now()),
    );
    try {
      final result = jsonMap(
        await _request('transport.seek', {'seconds': target}),
      );
      final position = jsonDouble(result['position'], target);
      _setTransport(
        transport.value.copyWith(position: position, receivedAtMicros: _now()),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> toggleRecord() async {
    if (transport.value.recording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    try {
      final result = jsonMap(await _request('transport.record.start'));
      _setTransport(
        transport.value.copyWith(
          recording: true,
          playing: true,
          recordStart: jsonDouble(result['recordStart']),
          receivedAtMicros: _now(),
        ),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> stopRecording() async {
    try {
      final result = jsonMap(await _request('transport.record.stop'));
      _setTransport(
        transport.value.copyWith(
          recording: false,
          position: jsonDouble(result['position'], estimatedPosition),
          receivedAtMicros: _now(),
        ),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> toggleMetronome() async {
    final enabled = !transport.value.metronome;
    try {
      final result = jsonMap(
        await _request('transport.metronome', {'enabled': enabled}),
      );
      _setTransport(
        transport.value.copyWith(
          metronome: jsonBool(result['metronome'], enabled),
        ),
      );
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setTempo(double bpm) async {
    final target = bpm.clamp(20.0, 300.0).toDouble();
    try {
      final result = jsonMap(
        await _request('transport.tempo', {'bpm': target}),
      );
      final tempo = jsonDouble(result['tempoBpm'], target);
      _setTransport(
        transport.value.copyWith(
          tempoBpm: tempo,
          revision: jsonInt(result['revision'], transport.value.revision),
        ),
      );
      final current = project.value;
      if (current != null) {
        project.value = current.copyWith(tempoBpm: tempo);
      }
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setTimeSignature(int numerator, int denominator) async {
    try {
      await _request('transport.timeSig', {
        'numerator': numerator,
        'denominator': denominator,
      });
      _setTransport(
        transport.value.copyWith(
          timeSigNum: numerator,
          timeSigDen: denominator,
        ),
      );
      final current = project.value;
      if (current != null) {
        project.value = current.copyWith(
          timeSigNum: numerator,
          timeSigDen: denominator,
        );
      }
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> undo() async {
    try {
      final result = jsonMap(await _request('project.undo'));
      if (jsonBool(result['changed'])) _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> redo() async {
    try {
      final result = jsonMap(await _request('project.redo'));
      if (jsonBool(result['changed'])) _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  void _setTransport(TransportState value) {
    transport.value = value;
  }

  // ---------------------------------------------------------------------------
  // Mixer (optimistic + coalesced)
  // ---------------------------------------------------------------------------

  void previewTrackVolume(int trackId, double volume) {
    final value = clampDouble(volume, 0, 2);
    _queueMix(trackId, 'volume', value);
    _setTrackOverride(trackId, volume: value);
  }

  void previewTrackPan(int trackId, double pan) {
    final value = clampDouble(pan, -1, 1);
    _queueMix(trackId, 'pan', value);
    _setTrackOverride(trackId, pan: value);
  }

  Future<void> commitTrackMix(
    int trackId, {
    double? volume,
    double? pan,
  }) async {
    final pending = _pendingMix.remove(trackId);
    final fields = <String, Object?>{'trackId': trackId, 'undo': true};
    if (pending?['volume'] != null) fields['volume'] = pending!['volume'];
    if (pending?['pan'] != null) fields['pan'] = pending!['pan'];
    if (volume != null) fields['volume'] = clampDouble(volume, 0, 2);
    if (pan != null) fields['pan'] = clampDouble(pan, -1, 1);
    if (!fields.containsKey('volume') && !fields.containsKey('pan')) {
      return;
    }
    _flushMixTimerIfEmpty();
    try {
      final result = jsonMap(await _request('mixer.setTrack', fields));
      _setTrackOverride(
        trackId,
        volume: fields['volume'] as double?,
        pan: fields['pan'] as double?,
        releaseRevision: jsonInt(result['revision']),
      );
    } on Object catch (raw) {
      _report(raw);
      _scheduleRefresh();
    }
  }

  void _queueMix(int trackId, String field, double value) {
    _pendingMix.putIfAbsent(trackId, () => <String, double>{})[field] = value;
    _mixTimer ??= Timer(const Duration(milliseconds: 55), _flushMix);
  }

  void _flushMix() {
    _mixTimer = null;
    if (_pendingMix.isEmpty) return;
    final pending = Map<int, Map<String, double>>.from(_pendingMix);
    _pendingMix.clear();
    for (final entry in pending.entries) {
      final fields = <String, Object?>{'trackId': entry.key, 'undo': false};
      fields.addAll(entry.value);
      unawaited(
        _request('mixer.setTrack', fields).catchError((Object raw) {
          _report(raw);
          _scheduleRefresh();
          return null;
        }),
      );
    }
  }

  void _flushMixTimerIfEmpty() {
    if (_pendingMix.isEmpty) {
      _mixTimer?.cancel();
      _mixTimer = null;
    }
  }

  Future<void> setTrackMute(int trackId, bool mute) async {
    _setTrackOverride(trackId, mute: mute);
    await _immediateTrackField(trackId, {'mute': mute});
  }

  Future<void> setTrackSolo(int trackId, bool solo) async {
    _setTrackOverride(trackId, solo: solo);
    await _immediateTrackField(trackId, {'solo': solo});
  }

  Future<void> setTrackArmed(int trackId, bool armed) async {
    _setTrackOverride(trackId, armed: armed);
    await _immediateTrackField(trackId, {'armed': armed});
  }

  Future<void> renameTrack(int trackId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _setTrackOverride(trackId, name: trimmed);
    await _immediateTrackField(trackId, {'name': trimmed});
  }

  Future<void> setTrackColor(int trackId, int colorIndex) async {
    _setTrackOverride(trackId, colorIndex: colorIndex);
    await _immediateTrackField(trackId, {'colorIndex': colorIndex});
  }

  Future<void> setTrackInput(int trackId, int inputChannel) async {
    _setTrackOverride(trackId, inputChannel: inputChannel);
    await _immediateTrackField(trackId, {'inputChannel': inputChannel});
  }

  Future<void> _immediateTrackField(
    int trackId,
    Map<String, Object?> fields,
  ) async {
    try {
      final result = jsonMap(
        await _request('mixer.setTrack', {'trackId': trackId, ...fields}),
      );
      _setTrackOverride(trackId, releaseRevision: jsonInt(result['revision']));
    } on Object catch (raw) {
      _report(raw);
      _scheduleRefresh();
    }
  }

  void previewMasterGain(double gain) {
    final value = clampDouble(gain, 0, 4);
    _pendingMaster = value;
    _masterOverride = _MasterOverride(
      value: value,
      expiresAtMicros: _now() + 4000000,
    );
    final current = project.value;
    if (current != null) project.value = current.withMasterGain(value);
    _startOverrideTimer();
    _masterMixTimer ??= Timer(
      const Duration(milliseconds: 55),
      _flushMasterMix,
    );
  }

  void _flushMasterMix() {
    _masterMixTimer = null;
    final value = _pendingMaster;
    _pendingMaster = null;
    if (value == null) return;
    unawaited(
      _request('mixer.setMaster', {'gain': value, 'undo': false}).catchError((
        Object raw,
      ) {
        _report(raw);
        _scheduleRefresh();
        return null;
      }),
    );
  }

  Future<void> commitMasterGain(double gain) async {
    final value = clampDouble(gain, 0, 4);
    _masterMixTimer?.cancel();
    _masterMixTimer = null;
    _pendingMaster = null;
    _masterOverride = _MasterOverride(
      value: value,
      expiresAtMicros: _now() + 4000000,
    );
    _startOverrideTimer();
    try {
      final result = jsonMap(
        await _request('mixer.setMaster', {'gain': value, 'undo': true}),
      );
      _masterOverride = _MasterOverride(
        value: value,
        expiresAtMicros: _now() + 1500000,
        releaseRevision: jsonInt(result['revision']),
      );
    } on Object catch (raw) {
      _report(raw);
      _scheduleRefresh();
    }
  }

  // ---------------------------------------------------------------------------
  // Tracks and clips
  // ---------------------------------------------------------------------------

  Future<int?> addTrack({
    required String name,
    required String type,
    required int colorIndex,
  }) async {
    try {
      final result = jsonMap(
        await _request('track.add', {
          'name': name,
          'type': type,
          'colorIndex': colorIndex,
        }),
      );
      final id = jsonInt(result['trackId']);
      if (id > 0) {
        selectedTrackId.value = id;
        selectedClipId.value = null;
      }
      _scheduleRefresh();
      return id > 0 ? id : null;
    } on Object catch (raw) {
      _report(raw);
      return null;
    }
  }

  Future<bool> removeTrack(int trackId) async {
    try {
      await _request('track.remove', {'trackId': trackId});
      if (selectedTrackId.value == trackId) selectedTrackId.value = null;
      final removedTrack = project.value?.trackById(trackId);
      final selectedClip = selectedClipId.value;
      if (selectedClip != null &&
          removedTrack != null &&
          removedTrack.clips.any((clip) => clip.id == selectedClip)) {
        selectedClipId.value = null;
      }
      _scheduleRefresh();
      return true;
    } on Object catch (raw) {
      _report(raw);
      return false;
    }
  }

  Future<bool> moveClip(int clipId, int trackId, double start) async {
    try {
      await _request('clip.move', {
        'clipId': clipId,
        'trackId': trackId,
        'start': math.max(0, start),
      });
      if (selectedClipId.value == clipId) {
        selectedTrackId.value = trackId;
      }
      _scheduleRefresh();
      return true;
    } on Object catch (raw) {
      _report(raw);
      return false;
    }
  }

  Future<bool> removeClip(int clipId) async {
    try {
      await _request('clip.remove', {'clipId': clipId});
      if (selectedClipId.value == clipId) selectedClipId.value = null;
      _scheduleRefresh();
      return true;
    } on Object catch (raw) {
      _report(raw);
      return false;
    }
  }

  Future<bool> splitClip(int clipId, double seconds) async {
    try {
      await _request('clip.split', {
        'clipId': clipId,
        'seconds': math.max(0, seconds),
      });
      _scheduleRefresh();
      return true;
    } on Object catch (raw) {
      _report(raw);
      return false;
    }
  }

  Future<void> setClipBounds(
    int clipId, {
    required double start,
    required double offset,
    required double length,
  }) async {
    try {
      await _request('clip.bounds', {
        'clipId': clipId,
        'start': math.max(0, start),
        'offset': math.max(0, offset),
        'length': math.max(0.02, length),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setClipFades(int clipId, double fadeIn, double fadeOut) async {
    try {
      await _request('clip.fades', {
        'clipId': clipId,
        'fadeIn': math.max(0, fadeIn),
        'fadeOut': math.max(0, fadeOut),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setClipGain(int clipId, double gain) async {
    try {
      await _request('clip.gain', {
        'clipId': clipId,
        'gain': math.max(0, gain),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  // ---------------------------------------------------------------------------
  // Plugins and effects
  // ---------------------------------------------------------------------------

  Future<List<PluginInfo>?> loadPlugins({bool force = false}) async {
    if (!force && plugins.value != null) return plugins.value;
    try {
      final result = await _request('plugins.list');
      final list = jsonList(result)
          .map((item) => PluginInfo.fromJson(jsonMap(item)))
          .toList(growable: false);
      plugins.value = list;
      return list;
    } on Object catch (raw) {
      _report(raw);
      rethrow;
    }
  }

  Future<List<FxParam>> fetchFxParams({
    required int trackId,
    required int slotKind,
    required int slotIndex,
  }) async {
    final result = jsonMap(
      await _request('fx.params', {
        'trackId': trackId,
        'slotKind': slotKind,
        'slotIndex': slotIndex,
      }),
    );
    return jsonList(
      result['params'],
    ).map((item) => FxParam.fromJson(jsonMap(item))).toList(growable: false);
  }

  Future<FxParam?> setFxParam({
    required int trackId,
    required int slotKind,
    required int slotIndex,
    required int paramIndex,
    required double value,
  }) async {
    try {
      final result = jsonMap(
        await _request('fx.setParam', {
          'trackId': trackId,
          'slotKind': slotKind,
          'slotIndex': slotIndex,
          'paramIndex': paramIndex,
          'value': clampDouble(value, 0, 1),
        }),
      );
      return FxParam(
        index: paramIndex,
        name: '',
        value: clampDouble(jsonDouble(result['value'], value), 0, 1),
        text: jsonString(result['text']),
      );
    } on Object catch (raw) {
      _report(raw);
      return null;
    }
  }

  Future<void> addFx(int trackId, int pluginIndex) async {
    try {
      await _request('fx.add', {
        'trackId': trackId,
        'pluginIndex': pluginIndex,
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> removeFx(int trackId, int slotIndex) async {
    try {
      await _request('fx.remove', {'trackId': trackId, 'slotIndex': slotIndex});
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setFxBypass(int trackId, int slotIndex, bool bypass) async {
    try {
      await _request('fx.setBypass', {
        'trackId': trackId,
        'slotIndex': slotIndex,
        'bypass': bypass,
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> addMasterFx(int pluginIndex) async {
    try {
      await _request('fx.master.add', {'pluginIndex': pluginIndex});
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> removeMasterFx(int slotIndex) async {
    try {
      await _request('fx.master.remove', {'slotIndex': slotIndex});
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setMasterFxBypass(int slotIndex, bool bypass) async {
    try {
      await _request('fx.master.setBypass', {
        'slotIndex': slotIndex,
        'bypass': bypass,
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  // ---------------------------------------------------------------------------
  // Automation
  // ---------------------------------------------------------------------------

  Future<void> setLaneAutomation(
    int trackId,
    int lane,
    List<AutomationPoint> points,
  ) async {
    try {
      await _request('automation.set', {
        'trackId': trackId,
        'lane': lane,
        'points': points.map((point) => point.toJson()).toList(),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> setParamAutomation({
    required int trackId,
    required int slotKind,
    required int slotIndex,
    required int paramIndex,
    required String name,
    required List<AutomationPoint> points,
  }) async {
    try {
      await _request('automation.param.set', {
        'trackId': trackId,
        'slotKind': slotKind,
        'slotIndex': slotIndex,
        'paramIndex': paramIndex,
        'name': name,
        'points': points.map((point) => point.toJson()).toList(),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> removeParamLane(int trackId, int laneIndex) async {
    try {
      await _request('automation.param.remove', {
        'trackId': trackId,
        'laneIndex': laneIndex,
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  Future<void> writeVolumeAutomation(
    int trackId,
    double time,
    double value,
  ) async {
    try {
      await _request('automation.writeVolume', {
        'trackId': trackId,
        'time': math.max(0, time),
        'value': clampDouble(value, 0, 1),
      });
      _scheduleRefresh();
    } on Object catch (raw) {
      _report(raw);
    }
  }

  // ---------------------------------------------------------------------------
  // Selection and refresh
  // ---------------------------------------------------------------------------

  void selectTrack(int? trackId, {bool clearClip = true}) {
    if (selectedTrackId.value != trackId) selectedTrackId.value = trackId;
    if (clearClip && selectedClipId.value != null) {
      selectedClipId.value = null;
    }
  }

  void selectClip(int? clipId) {
    selectedClipId.value = clipId;
    if (clipId != null) {
      final track = project.value?.trackForClip(clipId);
      if (track != null && selectedTrackId.value != track.id) {
        selectedTrackId.value = track.id;
      }
    }
  }

  void _ensureSelection({bool selectFirst = false}) {
    final current = project.value;
    if (current == null) return;
    final track = current.trackById(selectedTrackId.value);
    if (track == null) {
      selectedTrackId.value =
          selectFirst && current.tracks.isNotEmpty
              ? current.tracks.first.id
              : null;
    }
    if (selectedClipId.value != null &&
        current.clipById(selectedClipId.value) == null) {
      selectedClipId.value = null;
    }
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 90), () {
      _refreshTimer = null;
      unawaited(refreshState());
    });
  }

  Future<void> refreshState() async {
    if (_disposed) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    final token = ++_refreshToken;
    final generation = _generation;
    try {
      final result = jsonMap(await _request('state.get'));
      if (_disposed || token != _refreshToken || generation != _generation) {
        return;
      }
      final state = RemoteProject.fromJson(jsonMap(result['state']));
      project.value = _applyOverrides(state);
      transport.value = TransportState.fromJson(
        jsonMap(result['transport']),
        receivedAtMicros: _now(),
      );
      _ensureSelection();
    } on Object catch (raw) {
      if (_disposed || token != _refreshToken || generation != _generation) {
        return;
      }
      _report(raw);
    } finally {
      if (token == _refreshToken) {
        _refreshing = false;
        if (_refreshQueued && !_disposed) {
          _refreshQueued = false;
          _scheduleRefresh();
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Optimistic overrides
  // ---------------------------------------------------------------------------

  void _setTrackOverride(
    int trackId, {
    double? volume,
    double? pan,
    bool? mute,
    bool? solo,
    bool? armed,
    String? name,
    int? colorIndex,
    int? inputChannel,
    int? releaseRevision,
  }) {
    final override = (_trackOverrides[trackId] ?? _TrackOverride()).merge(
      volume: volume,
      pan: pan,
      mute: mute,
      solo: solo,
      armed: armed,
      name: name,
      colorIndex: colorIndex,
      inputChannel: inputChannel,
      releaseRevision: releaseRevision,
      expiresAtMicros: _now() + 4000000,
    );
    _trackOverrides[trackId] = override;
    final current = project.value;
    if (current != null) {
      final track = current.trackById(trackId);
      if (track != null) {
        project.value = current.withTrack(override.apply(track));
      }
    }
    _startOverrideTimer();
  }

  RemoteProject _applyOverrides(RemoteProject base) {
    if (_trackOverrides.isEmpty && _masterOverride == null) return base;
    final now = _now();
    _trackOverrides.removeWhere((_, override) {
      if (override.releaseRevision != null &&
          base.revision >= override.releaseRevision!) {
        return true;
      }
      return override.expiresAtMicros < now;
    });
    var result = base;
    for (final entry in _trackOverrides.entries) {
      final track = result.trackById(entry.key);
      if (track != null) {
        result = result.withTrack(entry.value.apply(track));
      }
    }
    final master = _masterOverride;
    if (master != null) {
      if (master.releaseRevision != null &&
          base.revision >= master.releaseRevision!) {
        _masterOverride = null;
      } else if (master.expiresAtMicros < now) {
        _masterOverride = null;
      } else {
        result = result.withMasterGain(master.value);
      }
    }
    return result;
  }

  void _startOverrideTimer() {
    if (_overrideTimer != null) return;
    _overrideTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      final expiration = _now() + 1;
      _trackOverrides.removeWhere(
        (_, override) => override.expiresAtMicros < expiration,
      );
      final master = _masterOverride;
      if (master != null && master.expiresAtMicros < expiration) {
        _masterOverride = null;
      }
      if (_trackOverrides.isEmpty && _masterOverride == null) {
        _overrideTimer?.cancel();
        _overrideTimer = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Meters
  // ---------------------------------------------------------------------------

  void _applyMeters(
    Map<int, double> trackPeaks,
    double masterLeft,
    double masterRight,
  ) {
    final now = _now();
    final dtMs =
        _lastMeterMicros == 0
            ? 50.0
            : ((now - _lastMeterMicros) / 1000).clamp(0.0, 500.0);
    _lastMeterMicros = now;
    final release = math.pow(0.9, dtMs / 50).toDouble();
    final holdFall = dtMs / 1000 * 0.45;

    final previous = meters.value;
    final levels = <int, MeterReading>{};
    final ids = <int>{...previous.tracks.keys, ...trackPeaks.keys};
    for (final id in ids) {
      final raw = trackPeaks[id] ?? 0;
      final old = previous.track(id);
      final peak = math.max(raw, old.peak * release).clamp(0.0, 1.0).toDouble();
      final hold =
          math.max(raw, old.hold - holdFall).clamp(0.0, 1.0).toDouble();
      levels[id] = MeterReading(peak: peak, hold: hold);
    }

    MeterReading update(MeterReading old, double raw) {
      final peak = math.max(raw, old.peak * release).clamp(0.0, 1.0).toDouble();
      final hold =
          math.max(raw, old.hold - holdFall).clamp(0.0, 1.0).toDouble();
      return MeterReading(peak: peak, hold: hold);
    }

    meters.value = MeterSnapshot(
      tracks: levels,
      masterLeft: update(previous.masterLeft, masterLeft),
      masterRight: update(previous.masterRight, masterRight),
      updatedAtMicros: now,
    );
  }

  // ---------------------------------------------------------------------------
  // App lifecycle
  // ---------------------------------------------------------------------------

  Future<void> onAppPaused() async {
    if (!hasSession) return;
    try {
      await _request('subscribe', {'meters': false});
    } on Object {
      // Best effort: the socket may already be suspended by Android.
    }
  }

  Future<void> onAppResumed() async {
    if (_manualDisconnect) return;
    if (!hasSession) {
      if (connection.value.phase == ConnectionPhase.authFailed) return;
      if (settings.autoReconnect && _host != null && _token != null) {
        await reconnectNow();
      }
      return;
    }
    try {
      await _request('subscribe', {'meters': true, 'metersHz': 20});
    } on Object {
      // The closed event will drive the reconnect path.
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Object?> _request(
    String command, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final api = _api;
    if (api == null || !api.isOpen) {
      throw const RemoteApiException(
        'not_connected',
        'Not connected to a studio',
      );
    }
    return api.request(command, fields);
  }

  void _report(Object raw) {
    if (_disposed) return;
    final failure = _asApiException(raw);
    error.value = UiError(
      message: failure.message,
      code: failure.code,
      sequence: ++_errorSequence,
    );
  }

  void _fail(String code) {
    if (_disposed) return;
    error.value = UiError(
      message: code,
      code: code,
      sequence: ++_errorSequence,
    );
  }

  RemoteApiException _asApiException(Object raw) {
    if (raw is RemoteApiException) return raw;
    return RemoteApiException('unexpected', raw.toString(), cause: raw);
  }

  void dispose() {
    _disposed = true;
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _mixTimer?.cancel();
    _masterMixTimer?.cancel();
    _overrideTimer?.cancel();
    _refreshTimer?.cancel();
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    final api = _api;
    _api = null;
    unawaited(api?.close());
    connection.dispose();
    project.dispose();
    transport.dispose();
    meters.dispose();
    server.dispose();
    selectedTrackId.dispose();
    selectedClipId.dispose();
    plugins.dispose();
    error.dispose();
    preferences.dispose();
  }
}

class _TrackOverride {
  _TrackOverride({
    this.volume,
    this.pan,
    this.mute,
    this.solo,
    this.armed,
    this.name,
    this.colorIndex,
    this.inputChannel,
    this.releaseRevision,
    this.expiresAtMicros = 0,
  });

  final double? volume;
  final double? pan;
  final bool? mute;
  final bool? solo;
  final bool? armed;
  final String? name;
  final int? colorIndex;
  final int? inputChannel;
  final int? releaseRevision;
  final int expiresAtMicros;

  _TrackOverride merge({
    double? volume,
    double? pan,
    bool? mute,
    bool? solo,
    bool? armed,
    String? name,
    int? colorIndex,
    int? inputChannel,
    int? releaseRevision,
    int? expiresAtMicros,
  }) {
    return _TrackOverride(
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      mute: mute ?? this.mute,
      solo: solo ?? this.solo,
      armed: armed ?? this.armed,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      inputChannel: inputChannel ?? this.inputChannel,
      releaseRevision: releaseRevision,
      expiresAtMicros: expiresAtMicros ?? this.expiresAtMicros,
    );
  }

  RemoteTrack apply(RemoteTrack track) {
    return track.copyWith(
      volume: volume,
      pan: pan,
      mute: mute,
      solo: solo,
      armed: armed,
      name: name,
      colorIndex: colorIndex,
      inputChannel: inputChannel,
    );
  }
}

class _MasterOverride {
  const _MasterOverride({
    required this.value,
    required this.expiresAtMicros,
    this.releaseRevision,
  });

  final double value;
  final int expiresAtMicros;
  final int? releaseRevision;
}
