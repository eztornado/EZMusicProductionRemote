// A small fake EZMusicProduction remote server for local UI development.
//
// It implements the same WebSocket + JSON protocol as the DAW
// (docs/design/remote-control.md) with an in-memory project, so the Flutter app
// can be exercised without launching the desktop application.
//
// Usage:
//   dart run tool/fake_server.dart
//   dart run tool/fake_server.dart --port=47823 --token=123456
//
// Then enter the printed host and pairing code in the app. On the Android
// emulator use 10.0.2.2 instead of 127.0.0.1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String _appName = 'EZMusicProduction';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--')) continue;
    final body = arg.substring(2);
    final split = body.indexOf('=');
    if (split < 0) {
      options[body] = 'true';
    } else {
      options[body.substring(0, split)] = body.substring(split + 1);
    }
  }

  final host = options['host'] ?? '0.0.0.0';
  final port = int.tryParse(options['port'] ?? '') ?? 47823;
  final token = options['token'] ?? '123456';
  final server = FakeRemoteServer(port: port, token: token);

  await server.start(host);
  stdout.writeln('EZ Remote fake studio');
  stdout.writeln('  pairing code: $token');
  stdout.writeln('  listen:       $host:$port');
  stdout.writeln('  discovery:    http://$host:$port/');
  stdout.writeln('  websocket:    ws://$host:$port/');
  if (host == '0.0.0.0') {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          stdout.writeln('  LAN:          ws://${address.address}:$port/');
        }
      }
    } on Object {
      // Network enumeration is best-effort.
    }
  }
  stdout.writeln('Press Ctrl+C to stop.');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}

class FakeRemoteServer {
  FakeRemoteServer({required this.port, required this.token});

  final int port;
  final String token;

  final List<_FakeClient> _clients = <_FakeClient>[];
  final Map<String, List<Map<String, Object?>>> _fxParams =
      <String, List<Map<String, Object?>>>{};
  final List<Map<String, Object?>> _plugins = <Map<String, Object?>>[
    _plugin(0, 'Compressor', false, 'VST3'),
    _plugin(1, 'Chorus', false, 'VST3'),
    _plugin(2, 'Reverb', false, 'VST3'),
    _plugin(3, 'Channel EQ', false, 'AU'),
    _plugin(4, 'Limiter', false, 'VST3'),
    _plugin(5, 'Analog Lab V', true, 'VST3'),
    _plugin(6, 'Studio Piano', true, 'VST3'),
    _plugin(7, 'Tape Echo', false, 'VST3'),
  ];

  final List<_FakeTrack> _tracks = <_FakeTrack>[];
  final List<Map<String, Object?>> _masterFx = <Map<String, Object?>>[];

  HttpServer? _http;
  Timer? _ticker;
  int _nextTrackId = 1;
  int _nextClipId = 1;
  int _revision = 1;
  bool _canUndo = false;
  bool _canRedo = false;
  final String _projectName = 'Fake Session';
  double _tempo = 120;
  int _timeSigNum = 4;
  int _timeSigDen = 4;
  double _duration = 64;
  double _masterGain = 1;
  double _position = 0;
  double _recordStart = 0;
  bool _playing = false;
  bool _recording = false;
  bool _metronome = false;
  double _meterPhase = 0;
  final Map<int, double> _meterPeaks = <int, double>{};

  static Map<String, Object?> _plugin(
    int index,
    String name,
    bool isInstrument,
    String format,
  ) {
    return <String, Object?>{
      'index': index,
      'name': name,
      'isInstrument': isInstrument,
      'format': format,
    };
  }

  Future<void> start(String host) async {
    _seedProject();
    final address =
        host == '0.0.0.0'
            ? InternetAddress.anyIPv4
            : InternetAddress.tryParse(host) ?? InternetAddress.loopbackIPv4;
    _http = await HttpServer.bind(address, port, shared: true);
    _http!.listen(_handleHttp);
    _ticker = Timer.periodic(const Duration(milliseconds: 20), (_) => _tick());
  }

  Future<void> stop() async {
    _ticker?.cancel();
    for (final client in List<_FakeClient>.of(_clients)) {
      try {
        await client.socket.close(WebSocketStatus.normalClosure);
      } on Object {
        // Already closed.
      }
    }
    _clients.clear();
    await _http?.close(force: true);
    _http = null;
  }

  void _seedProject() {
    _masterFx.add(_fxSlot(0, 'Limiter'));

    final drums = _addTrackInternal(
      name: 'Drums',
      type: 'audio',
      colorIndex: 0,
      volume: 0.85,
    );
    drums.fx.add(_fxSlot(0, 'Compressor'));
    _fxParams['${drums.id}:0:0'] = _params(<String>[
      'Threshold',
      'Ratio',
      'Attack',
      'Release',
    ]);
    drums.clips.add(
      _newClip(
        kind: 'audio',
        start: 0,
        length: 8,
        offset: 0,
        notes: const <Map<String, Object?>>[],
      ),
    );

    final bass = _addTrackInternal(
      name: 'Bass',
      type: 'instrument',
      colorIndex: 7,
      volume: 0.8,
      pan: -0.1,
      instrument: 'Analog Lab V',
    );
    bass.fx
      ..add(_fxSlot(0, 'Chorus'))
      ..add(_fxSlot(1, 'Reverb'));
    _fxParams['${bass.id}:0:0'] = _params(<String>['Rate', 'Depth', 'Mix']);
    _fxParams['${bass.id}:0:1'] = _params(<String>['Size', 'Decay', 'Mix']);
    _fxParams['${bass.id}:1:0'] = _params(<String>[
      'Brightness',
      'Attack',
      'Release',
      'Glide',
    ]);
    bass.volumeAutomation.addAll(<Map<String, Object?>>[
      <String, Object?>{'t': 0.0, 'v': 0.8},
      <String, Object?>{'t': 8.0, 'v': 0.55},
      <String, Object?>{'t': 16.0, 'v': 0.9},
      <String, Object?>{'t': 24.0, 'v': 0.7},
    ]);
    bass.panAutomation.addAll(<Map<String, Object?>>[
      <String, Object?>{'t': 0.0, 'v': 0.5},
      <String, Object?>{'t': 12.0, 'v': 0.3},
      <String, Object?>{'t': 24.0, 'v': 0.65},
    ]);
    bass.clips.add(
      _newClip(
        kind: 'midi',
        start: 0,
        length: 32,
        offset: 0,
        notes: <Map<String, Object?>>[
          _note(36, 0.9, 0, 0.5),
          _note(36, 0.8, 1, 0.5),
          _note(43, 0.75, 2, 0.5),
          _note(43, 0.8, 3, 0.5),
        ],
      ),
    );

    final keys = _addTrackInternal(
      name: 'Keys',
      type: 'instrument',
      colorIndex: 8,
      volume: 0.7,
      pan: 0.15,
      instrument: 'Studio Piano',
    );
    keys.fx.add(_fxSlot(0, 'Channel EQ'));
    _fxParams['${keys.id}:0:0'] = _params(<String>['Low', 'Mid', 'High', 'Q']);
    _fxParams['${keys.id}:1:0'] = _params(<String>[
      'Brightness',
      'Velocity',
      'Pedal',
    ]);
    keys.paramLanes.add(<String, Object?>{
      'index': 0,
      'slotKind': 1,
      'slotIndex': 0,
      'paramIndex': 0,
      'name': 'Brightness',
      'points': <Map<String, Object?>>[
        <String, Object?>{'t': 0.0, 'v': 0.55},
        <String, Object?>{'t': 10.0, 'v': 0.8},
        <String, Object?>{'t': 20.0, 'v': 0.45},
      ],
    });
    keys.clips.add(
      _newClip(
        kind: 'midi',
        start: 4,
        length: 20,
        offset: 0,
        notes: <Map<String, Object?>>[
          _note(60, 0.8, 0, 1),
          _note(64, 0.7, 1, 1),
          _note(67, 0.75, 2, 1),
        ],
      ),
    );

    final vocal = _addTrackInternal(
      name: 'Vocal',
      type: 'audio',
      colorIndex: 12,
      volume: 0.9,
    );
    vocal.clips.add(
      _newClip(
        kind: 'audio',
        start: 16,
        length: 8,
        offset: 0,
        notes: const <Map<String, Object?>>[],
      ),
    );

    _duration = 64;
    _revision = 1;
  }

  _FakeTrack _addTrackInternal({
    required String name,
    required String type,
    required int colorIndex,
    double volume = 1,
    double pan = 0,
    String instrument = '',
  }) {
    final track = _FakeTrack(
      id: _nextTrackId++,
      name: name,
      type: type,
      colorIndex: colorIndex,
      volume: volume,
      pan: pan,
      instrument: instrument,
    );
    _tracks.add(track);
    return track;
  }

  Map<String, Object?> _fxSlot(int index, String name) {
    return <String, Object?>{'index': index, 'name': name, 'bypass': false};
  }

  Map<String, Object?> _newClip({
    required String kind,
    required double start,
    required double length,
    required double offset,
    required List<Map<String, Object?>> notes,
  }) {
    return <String, Object?>{
      'id': _nextClipId++,
      'kind': kind,
      'start': start,
      'length': length,
      'offset': offset,
      'gain': 1.0,
      'fadeIn': 0.0,
      'fadeOut': 0.0,
      'muted': false,
      'notes': notes,
    };
  }

  Map<String, Object?> _note(
    int pitch,
    double velocity,
    double start,
    double length,
  ) {
    return <String, Object?>{
      'pitch': pitch,
      'velocity': velocity,
      'start': start,
      'length': length,
    };
  }

  List<Map<String, Object?>> _params(List<String> names) {
    return <Map<String, Object?>>[
      for (var index = 0; index < names.length; index++)
        <String, Object?>{
          'index': index,
          'name': names[index],
          'value': 0.5,
          'text': '50%',
        },
    ];
  }

  // ---------------------------------------------------------------------------
  // HTTP discovery and WebSocket upgrade
  // ---------------------------------------------------------------------------

  Future<void> _handleHttp(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _attach(socket);
      } on Object catch (error) {
        stderr.writeln('WebSocket upgrade failed: $error');
      }
      return;
    }

    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    response.headers.contentType = ContentType.json;
    response.write(
      jsonEncode(<String, Object?>{
        'app': _appName,
        'protocol': 1,
        'transport': 'websocket+json',
        'port': port,
        'requiresToken': true,
      }),
    );
    await response.close();
  }

  void _attach(WebSocket socket) {
    final client = _FakeClient(socket);
    _clients.add(client);
    socket.pingInterval = const Duration(seconds: 20);
    stdout.writeln('client connected (${_clients.length} total)');
    socket.listen(
      (raw) => _handleMessage(client, raw),
      onDone: () {
        _clients.remove(client);
        stdout.writeln('client disconnected (${_clients.length} total)');
      },
      onError: (Object error) {
        _clients.remove(client);
        stderr.writeln('client error: $error');
      },
      cancelOnError: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Protocol dispatch
  // ---------------------------------------------------------------------------

  void _handleMessage(_FakeClient client, Object? raw) {
    if (raw is! String) {
      _sendError(client, null, 'bad_json', 'Text frames only');
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      _sendError(client, null, 'bad_json', 'Invalid JSON');
      return;
    }
    if (decoded is! Map) {
      _sendError(client, null, 'bad_request', 'Expected an object');
      return;
    }
    final message = Map<String, Object?>.from(decoded);
    final id = message['id'] is num ? (message['id'] as num).toInt() : null;
    final command = message['cmd'] is String ? message['cmd'] as String : '';

    if (command.isEmpty) {
      _sendError(client, id, 'bad_request', 'Missing cmd');
      return;
    }

    if (!client.authenticated) {
      if (command == 'hello') {
        _handleHello(client, id, message);
      } else if (command == 'ping') {
        _sendResult(client, id, <String, Object?>{
          'pong': true,
          'time': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        _sendError(
          client,
          id,
          'auth_required',
          'Send hello before using this command',
        );
      }
      return;
    }

    try {
      _dispatch(client, id, command, message);
    } on _ProtocolError catch (error) {
      _sendError(client, id, error.code, error.message);
    } on Object catch (error) {
      stderr.writeln('command $command failed: $error');
      _sendError(client, id, 'unknown', '$error');
    }
  }

  void _handleHello(_FakeClient client, int? id, Map<String, Object?> message) {
    final supplied = _string(message['token']);
    if (supplied != token) {
      client.authAttempts++;
      _sendError(client, id, 'auth_failed', 'Invalid pairing code');
      if (client.authAttempts >= 5) {
        stdout.writeln('too many failed hello attempts; closing client');
        unawaited(client.socket.close(WebSocketStatus.policyViolation));
      }
      return;
    }

    client.authenticated = true;
    client.clientName = _string(
      (message['client'] is Map)
          ? Map<String, Object?>.from(message['client'] as Map)['name']
          : null,
      fallback: 'Fake client',
    );
    stdout.writeln('client authenticated: ${client.clientName}');
    _sendResult(client, id, <String, Object?>{
      'protocol': 1,
      'clientId': _clients.indexOf(client) + 1,
      'server': <String, Object?>{
        'app': _appName,
        'port': port,
        'requiresToken': true,
        'protocol': 1,
        'projectName': _projectName,
        'capabilities': <String>[
          'transport',
          'timeline',
          'mixer',
          'fx',
          'automation',
          'meters',
          'plugins',
        ],
      },
      'state': _projectJson(),
      'transport': _transportJson(),
    });
    _sendTransport(client);
  }

  void _dispatch(
    _FakeClient client,
    int? id,
    String command,
    Map<String, Object?> message,
  ) {
    switch (command) {
      case 'ping':
        _sendResult(client, id, <String, Object?>{
          'pong': true,
          'time': DateTime.now().millisecondsSinceEpoch,
        });
      case 'state.get':
        _sendResult(client, id, <String, Object?>{
          'state': _projectJson(),
          'transport': _transportJson(),
        });
      case 'transport.get':
        _sendResult(client, id, _transportJson());
      case 'subscribe':
        client.meters = _bool(message['meters'], fallback: client.meters);
        client.metersHz = _int(
          message['metersHz'],
          fallback: client.metersHz,
        ).clamp(1, 30);
        client.lastMetersMs = 0;
        _sendResult(client, id, <String, Object?>{
          'meters': client.meters,
          'metersHz': client.metersHz,
        });
      case 'transport.play':
        _playing = true;
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{'playing': true});
      case 'transport.pause':
        _playing = false;
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{'playing': false});
      case 'transport.stop':
        _playing = false;
        _recording = false;
        _position = 0;
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{
          'playing': false,
          'position': 0,
        });
      case 'transport.seek':
        _position = _double(
          message.containsKey('seconds')
              ? message['seconds']
              : message['position'],
        ).clamp(0.0, _duration);
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{'position': _position});
      case 'transport.record.start':
        _recordStart = _position;
        _playing = true;
        _recording = true;
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{
          'recording': true,
          'recordStart': _recordStart,
        });
      case 'transport.record.stop':
        _recording = false;
        _playing = false;
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{
          'recording': false,
          'position': _position,
        });
      case 'transport.metronome':
        _metronome = _bool(message['enabled'], fallback: _metronome);
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{'metronome': _metronome});
      case 'transport.tempo':
        _tempo = _double(message['bpm'], fallback: _tempo).clamp(20.0, 300.0);
        _touch();
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{
          'tempoBpm': _tempo,
          'revision': _revision,
        });
      case 'transport.timeSig':
        _timeSigNum = _int(
          message['numerator'],
          fallback: _timeSigNum,
        ).clamp(1, 32);
        _timeSigDen = _int(
          message['denominator'],
          fallback: _timeSigDen,
        ).clamp(1, 32);
        _touch();
        _broadcastTransport();
        _sendResult(client, id, <String, Object?>{
          'numerator': _timeSigNum,
          'denominator': _timeSigDen,
          'revision': _revision,
        });
      case 'project.undo':
        _canUndo = false;
        _canRedo = true;
        _revision++;
        _broadcastProject();
        _sendResult(client, id, <String, Object?>{
          'changed': true,
          'revision': _revision,
        });
      case 'project.redo':
        _canUndo = true;
        _canRedo = false;
        _revision++;
        _broadcastProject();
        _sendResult(client, id, <String, Object?>{
          'changed': true,
          'revision': _revision,
        });
      case 'mixer.setTrack':
        _setTrack(message);
        _touch();
        _sendResult(client, id, <String, Object?>{
          'trackId': _int(message['trackId']),
          'revision': _revision,
        });
      case 'mixer.setMaster':
        _masterGain = _double(
          message['gain'],
          fallback: _masterGain,
        ).clamp(0.0, 4.0);
        _touch();
        _sendResult(client, id, <String, Object?>{
          'gain': _masterGain,
          'revision': _revision,
        });
      case 'track.add':
        _trackAdd(message);
        _touch();
        _sendResult(client, id, <String, Object?>{
          'trackId': _tracks.last.id,
          'revision': _revision,
        });
      case 'track.remove':
        _trackRemove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.move':
        _clipMove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.remove':
        _clipRemove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.split':
        _clipSplit(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.bounds':
        _clipBounds(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.fades':
        _clipFades(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'clip.gain':
        _clipGain(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'plugins.list':
        _sendResult(client, id, _plugins);
      case 'fx.params':
        _sendResult(client, id, _fxParamsFor(message));
      case 'fx.setParam':
        _sendResult(client, id, _fxSetParam(message));
      case 'fx.setBypass':
        _fxSetBypass(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'fx.remove':
        _fxRemove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'fx.add':
        _fxAdd(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'fx.master.add':
        _fxMasterAdd(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'fx.master.remove':
        _fxMasterRemove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'fx.master.setBypass':
        _fxMasterBypass(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'automation.set':
        _automationSet(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'automation.param.set':
        _automationParamSet(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'automation.param.remove':
        _automationParamRemove(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      case 'automation.writeVolume':
        _automationWriteVolume(message);
        _touch();
        _sendResult(client, id, <String, Object?>{'revision': _revision});
      default:
        _sendError(client, id, 'unknown_command', 'Unknown command: $command');
    }
  }

  // ---------------------------------------------------------------------------
  // Mixer / timeline mutations
  // ---------------------------------------------------------------------------

  _FakeTrack _track(int? id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    throw _ProtocolError('not_found', 'track not found: $id');
  }

  void _setTrack(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    if (message.containsKey('volume')) {
      track.volume = _double(
        message['volume'],
        fallback: track.volume,
      ).clamp(0.0, 2.0);
    }
    if (message.containsKey('pan')) {
      track.pan = _double(message['pan'], fallback: track.pan).clamp(-1.0, 1.0);
    }
    if (message.containsKey('mute')) {
      track.mute = _bool(message['mute'], fallback: track.mute);
    }
    if (message.containsKey('solo')) {
      track.solo = _bool(message['solo'], fallback: track.solo);
    }
    if (message.containsKey('armed')) {
      track.armed = _bool(message['armed'], fallback: track.armed);
    }
    if (message.containsKey('inputChannel')) {
      track.inputChannel = _int(
        message['inputChannel'],
        fallback: track.inputChannel,
      );
    }
    if (message.containsKey('name')) {
      final name = _string(message['name']).trim();
      if (name.isNotEmpty) track.name = name;
    }
    if (message.containsKey('colorIndex')) {
      track.colorIndex = _int(
        message['colorIndex'],
        fallback: track.colorIndex,
      );
    }
  }

  void _trackAdd(Map<String, Object?> message) {
    final rawType = message['type'];
    final type =
        rawType is num
            ? (rawType.toInt() == 1 ? 'instrument' : 'audio')
            : _string(rawType, fallback: 'audio') == 'instrument'
            ? 'instrument'
            : 'audio';
    _addTrackInternal(
      name:
          _string(message['name'], fallback: 'Track').trim().isEmpty
              ? 'Track'
              : _string(message['name']).trim(),
      type: type,
      colorIndex: _int(message['colorIndex']).clamp(0, 15),
    );
  }

  void _trackRemove(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    _tracks.remove(track);
  }

  _ClipRef _clip(int? id) {
    for (final track in _tracks) {
      for (final clip in track.clips) {
        if (clip['id'] == id) return _ClipRef(track, clip);
      }
    }
    throw _ProtocolError('not_found', 'clip not found: $id');
  }

  void _clipMove(Map<String, Object?> message) {
    final ref = _clip(_int(message['clipId']));
    final target = _track(_int(message['trackId']));
    ref.track.clips.remove(ref.clip);
    ref.clip['start'] = _double(message['start']).clamp(0.0, double.infinity);
    target.clips.add(ref.clip);
  }

  void _clipRemove(Map<String, Object?> message) {
    final ref = _clip(_int(message['clipId']));
    ref.track.clips.remove(ref.clip);
  }

  void _clipSplit(Map<String, Object?> message) {
    final ref = _clip(_int(message['clipId']));
    final clip = ref.clip;
    final start = _double(clip['start']);
    final length = _double(clip['length']);
    final offset = _double(clip['offset']);
    final at = _double(message['seconds']);
    if (at <= start + 0.02 || at >= start + length - 0.02) {
      throw _ProtocolError(
        'invalid_argument',
        'split point must be inside the clip',
      );
    }
    final leftLength = at - start;
    final rightLength = length - leftLength;
    clip['length'] = leftLength;
    final right =
        Map<String, Object?>.from(clip)
          ..['id'] = _nextClipId++
          ..['start'] = at
          ..['length'] = rightLength
          ..['offset'] = offset + leftLength;
    ref.track.clips.add(right);
  }

  void _clipBounds(Map<String, Object?> message) {
    final clip = _clip(_int(message['clipId'])).clip;
    clip['start'] = _double(
      message['start'],
      fallback: _double(clip['start']),
    ).clamp(0.0, double.infinity);
    clip['offset'] = _double(
      message['offset'],
      fallback: _double(clip['offset']),
    ).clamp(0.0, double.infinity);
    clip['length'] = _double(
      message['length'],
      fallback: _double(clip['length']),
    ).clamp(0.02, double.infinity);
  }

  void _clipFades(Map<String, Object?> message) {
    final clip = _clip(_int(message['clipId'])).clip;
    clip['fadeIn'] = _double(
      message['fadeIn'],
      fallback: _double(clip['fadeIn']),
    ).clamp(0.0, double.infinity);
    clip['fadeOut'] = _double(
      message['fadeOut'],
      fallback: _double(clip['fadeOut']),
    ).clamp(0.0, double.infinity);
  }

  void _clipGain(Map<String, Object?> message) {
    final clip = _clip(_int(message['clipId'])).clip;
    clip['gain'] = _double(
      message['gain'],
      fallback: _double(clip['gain']),
    ).clamp(0.0, 4.0);
  }

  // ---------------------------------------------------------------------------
  // FX
  // ---------------------------------------------------------------------------

  Map<String, Object?> _fxParamsFor(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final slotKind = _int(message['slotKind']);
    final slotIndex = _int(message['slotIndex']);
    final key = '${track.id}:$slotKind:$slotIndex';
    var params = _fxParams[key];
    if (params == null) {
      params = _params(<String>['Drive', 'Tone', 'Mix']);
      _fxParams[key] = params;
    }
    return <String, Object?>{
      'slotKind': slotKind,
      'slotIndex': slotIndex,
      'params': params,
    };
  }

  Map<String, Object?> _fxSetParam(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final slotKind = _int(message['slotKind']);
    final slotIndex = _int(message['slotIndex']);
    final key = '${track.id}:$slotKind:$slotIndex';
    final params = _fxParams.putIfAbsent(
      key,
      () => _params(<String>['Drive', 'Tone', 'Mix']),
    );
    final index = _int(message['paramIndex']);
    final value = _double(message['value']).clamp(0.0, 1.0);
    Map<String, Object?>? param;
    for (final candidate in params) {
      if (candidate['index'] == index) {
        param = candidate;
        break;
      }
    }
    if (param == null) {
      throw _ProtocolError('not_found', 'parameter not found: $index');
    }
    param['value'] = value;
    param['text'] = '${(value * 100).round()}%';
    return <String, Object?>{'value': value, 'text': param['text']};
  }

  void _fxSetBypass(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final slot = _slot(track.fx, _int(message['slotIndex']));
    slot['bypass'] = _bool(message['bypass'], fallback: false);
  }

  void _fxRemove(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    track.fx.removeAt(_slotIndex(track.fx, _int(message['slotIndex'])));
    _reindex(track.fx);
  }

  void _fxAdd(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final plugin = _pluginByIndex(_int(message['pluginIndex']));
    if (_bool(plugin['isInstrument'])) {
      throw _ProtocolError(
        'invalid_argument',
        'use an effect plugin for an insert slot',
      );
    }
    final index = track.fx.length;
    track.fx.add(_fxSlot(index, _string(plugin['name'], fallback: 'Effect')));
    _fxParams['${track.id}:0:$index'] = _params(<String>[
      'Drive',
      'Tone',
      'Mix',
    ]);
  }

  void _fxMasterAdd(Map<String, Object?> message) {
    final plugin = _pluginByIndex(_int(message['pluginIndex']));
    if (_bool(plugin['isInstrument'])) {
      throw _ProtocolError(
        'invalid_argument',
        'use an effect plugin for the master chain',
      );
    }
    _masterFx.add(
      _fxSlot(_masterFx.length, _string(plugin['name'], fallback: 'Effect')),
    );
  }

  void _fxMasterRemove(Map<String, Object?> message) {
    _masterFx.removeAt(_slotIndex(_masterFx, _int(message['slotIndex'])));
    _reindex(_masterFx);
  }

  void _fxMasterBypass(Map<String, Object?> message) {
    final slot = _slot(_masterFx, _int(message['slotIndex']));
    slot['bypass'] = _bool(message['bypass'], fallback: false);
  }

  Map<String, Object?> _pluginByIndex(int index) {
    for (final plugin in _plugins) {
      if (plugin['index'] == index) return plugin;
    }
    throw _ProtocolError('not_found', 'plugin not found: $index');
  }

  Map<String, Object?> _slot(List<Map<String, Object?>> slots, int index) {
    return slots[_slotIndex(slots, index)];
  }

  int _slotIndex(List<Map<String, Object?>> slots, int index) {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i]['index'] == index) return i;
    }
    throw _ProtocolError('not_found', 'slot not found: $index');
  }

  void _reindex(List<Map<String, Object?>> slots) {
    for (var i = 0; i < slots.length; i++) {
      slots[i]['index'] = i;
    }
  }

  // ---------------------------------------------------------------------------
  // Automation
  // ---------------------------------------------------------------------------

  List<Map<String, Object?>> _points(Object? raw) {
    final points = <Map<String, Object?>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, Object?>.from(item);
        points.add(<String, Object?>{
          't': _double(
            map.containsKey('t') ? map['t'] : map['time'],
          ).clamp(0.0, double.infinity),
          'v': _double(
            map.containsKey('v') ? map['v'] : map['value'],
          ).clamp(0.0, 1.0),
        });
      }
    }
    points.sort((a, b) => _double(a['t']).compareTo(_double(b['t'])));
    return points;
  }

  void _automationSet(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final lane = _int(message['lane']);
    final points = _points(message['points']);
    switch (lane) {
      case 0:
        track.volumeAutomation = points;
      case 1:
        track.panAutomation = points;
      case 2:
        track.sustainAutomation = points;
      default:
        throw _ProtocolError('invalid_argument', 'invalid automation lane');
    }
  }

  void _automationParamSet(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final slotKind = _int(message['slotKind']);
    final slotIndex = _int(message['slotIndex']);
    final paramIndex = _int(message['paramIndex']);
    final name = _string(message['name'], fallback: 'Parameter');
    final points = _points(message['points']);
    for (final lane in track.paramLanes) {
      if (lane['slotKind'] == slotKind &&
          lane['slotIndex'] == slotIndex &&
          lane['paramIndex'] == paramIndex) {
        lane['name'] = name;
        lane['points'] = points;
        return;
      }
    }
    var next = 0;
    for (final lane in track.paramLanes) {
      next = math.max(next, _int(lane['index']) + 1);
    }
    track.paramLanes.add(<String, Object?>{
      'index': next,
      'slotKind': slotKind,
      'slotIndex': slotIndex,
      'paramIndex': paramIndex,
      'name': name,
      'points': points,
    });
  }

  void _automationParamRemove(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final index = _int(message['laneIndex']);
    final before = track.paramLanes.length;
    track.paramLanes.removeWhere((lane) => lane['index'] == index);
    if (track.paramLanes.length == before) {
      throw _ProtocolError('not_found', 'lane not found: $index');
    }
  }

  void _automationWriteVolume(Map<String, Object?> message) {
    final track = _track(_int(message['trackId']));
    final time = _double(message['time']).clamp(0.0, double.infinity);
    final value = _double(message['value']).clamp(0.0, 1.0);
    final points = List<Map<String, Object?>>.of(track.volumeAutomation);
    var replaced = false;
    for (final point in points) {
      if ((_double(point['t']) - time).abs() < 0.005) {
        point['v'] = value;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      points.add(<String, Object?>{'t': time, 'v': value});
    }
    points.sort((a, b) => _double(a['t']).compareTo(_double(b['t'])));
    track.volumeAutomation = points;
  }

  // ---------------------------------------------------------------------------
  // State serialization and events
  // ---------------------------------------------------------------------------

  Map<String, Object?> _projectJson() {
    return <String, Object?>{
      'revision': _revision,
      'canUndo': _canUndo,
      'canRedo': _canRedo,
      'name': _projectName,
      'sampleRate': 48000.0,
      'tempoBpm': _tempo,
      'timeSigNum': _timeSigNum,
      'timeSigDen': _timeSigDen,
      'duration': _duration,
      'masterGain': _masterGain,
      'inputQuantize': 0.0,
      'masterFx': _masterFx,
      'tracks': _tracks.map((track) => track.toJson()).toList(),
    };
  }

  Map<String, Object?> _transportJson() {
    return <String, Object?>{
      'playing': _playing,
      'recording': _recording,
      'position': _position,
      'duration': _duration,
      'recordStart': _recordStart,
      'metronome': _metronome,
      'tempoBpm': _tempo,
      'timeSigNum': _timeSigNum,
      'timeSigDen': _timeSigDen,
      'revision': _revision,
    };
  }

  void _touch() {
    _revision++;
    _canUndo = true;
    _canRedo = false;
    _broadcastProject();
  }

  void _tick() {
    if (_playing) {
      _position += 0.02;
      if (_position >= _duration) {
        _position = 0;
        _playing = false;
        _recording = false;
        _broadcastTransport();
      }
    }
    _meterPhase += 0.09;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final track in _tracks) {
      final target =
          _playing
              ? (0.12 +
                  0.62 * (0.5 + 0.5 * math.sin(_meterPhase * 1.7 + track.id)))
              : 0.0;
      final previous = _meterPeaks[track.id] ?? 0;
      _meterPeaks[track.id] = previous + (target - previous) * 0.35;
    }

    for (final client in List<_FakeClient>.of(_clients)) {
      if (!client.authenticated) continue;
      final transportInterval = _playing ? 100 : 2000;
      if (now - client.lastTransportMs >= transportInterval) {
        client.lastTransportMs = now;
        _sendTransport(client);
      }
      if (client.meters &&
          now - client.lastMetersMs >= (1000 / client.metersHz).round()) {
        client.lastMetersMs = now;
        _sendMeters(client);
      }
    }
  }

  void _broadcastProject() {
    final data = _projectJson();
    for (final client in List<_FakeClient>.of(_clients)) {
      if (!client.authenticated) continue;
      _send(client, <String, Object?>{
        'v': 1,
        'event': 'project',
        'data': data,
      });
    }
  }

  void _broadcastTransport() {
    for (final client in List<_FakeClient>.of(_clients)) {
      if (!client.authenticated) continue;
      _sendTransport(client);
    }
  }

  void _sendTransport(_FakeClient client) {
    _send(client, <String, Object?>{
      'v': 1,
      'event': 'transport',
      'data': _transportJson(),
    });
  }

  void _sendMeters(_FakeClient client) {
    final tracks = <Map<String, Object?>>[];
    var master = 0.0;
    for (final track in _tracks) {
      final peak = (_meterPeaks[track.id] ?? 0).clamp(0.0, 1.0);
      master = math.max(master, peak);
      tracks.add(<String, Object?>{'id': track.id, 'peak': peak});
    }
    _send(client, <String, Object?>{
      'v': 1,
      'event': 'meters',
      'data': <String, Object?>{
        'tracks': tracks,
        'master': <double>[
          (master * 0.92).clamp(0.0, 1.0),
          (master * 0.86).clamp(0.0, 1.0),
        ],
      },
    });
  }

  void _sendResult(_FakeClient client, int? id, Object? result) {
    final message = <String, Object?>{'v': 1, 'ok': true, 'result': result};
    if (id != null) message['id'] = id;
    _send(client, message);
  }

  void _sendError(_FakeClient client, int? id, String code, String message) {
    final payload = <String, Object?>{
      'v': 1,
      'ok': false,
      'error': <String, Object?>{'code': code, 'message': message},
    };
    if (id != null) payload['id'] = id;
    _send(client, payload);
  }

  void _send(_FakeClient client, Map<String, Object?> message) {
    if (client.socket.readyState != WebSocket.open) return;
    try {
      client.socket.add(jsonEncode(message));
    } on Object {
      // The close handler will clean up.
    }
  }

  // ---------------------------------------------------------------------------
  // JSON helpers
  // ---------------------------------------------------------------------------

  static String _string(Object? value, {String fallback = ''}) {
    return value is String ? value : fallback;
  }

  static bool _bool(Object? value, {bool fallback = false}) {
    return value is bool ? value : fallback;
  }

  static int _int(Object? value, {int fallback = 0}) {
    return value is num ? value.toInt() : fallback;
  }

  static double _double(Object? value, {double fallback = 0}) {
    return value is num ? value.toDouble() : fallback;
  }
}

class _FakeClient {
  _FakeClient(this.socket);

  final WebSocket socket;
  bool authenticated = false;
  int authAttempts = 0;
  String clientName = 'Fake client';
  bool meters = false;
  int metersHz = 20;
  int lastTransportMs = 0;
  int lastMetersMs = 0;
}

class _FakeTrack {
  _FakeTrack({
    required this.id,
    required this.name,
    required this.type,
    required this.colorIndex,
    required this.volume,
    required this.pan,
    required this.instrument,
  });

  final int id;
  String name;
  String type;
  int colorIndex;
  double volume;
  double pan;
  bool mute = false;
  bool solo = false;
  bool armed = false;
  int inputChannel = 0;
  String instrument;
  String midiFx = '';
  final List<Map<String, Object?>> fx = <Map<String, Object?>>[];
  List<Map<String, Object?>> volumeAutomation = <Map<String, Object?>>[];
  List<Map<String, Object?>> panAutomation = <Map<String, Object?>>[];
  List<Map<String, Object?>> sustainAutomation = <Map<String, Object?>>[];
  final List<Map<String, Object?>> paramLanes = <Map<String, Object?>>[];
  final List<Map<String, Object?>> clips = <Map<String, Object?>>[];

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'name': name,
      'colorIndex': colorIndex,
      'volume': volume,
      'pan': pan,
      'mute': mute,
      'solo': solo,
      'armed': armed,
      'inputChannel': inputChannel,
      'instrument': instrument,
      'midiFx': midiFx,
      'fx': fx,
      'automation': <String, Object?>{
        'volume': volumeAutomation,
        'pan': panAutomation,
        'sustain': sustainAutomation,
        'params': paramLanes,
      },
      'clips': clips,
    };
  }
}

class _ClipRef {
  const _ClipRef(this.track, this.clip);

  final _FakeTrack track;
  final Map<String, Object?> clip;
}

class _ProtocolError implements Exception {
  const _ProtocolError(this.code, this.message);

  final String code;
  final String message;
}
