import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/json.dart';
import '../core/network.dart';
import '../models/project.dart';
import '../models/session.dart';
import 'remote_api.dart';

/// WebSocket + JSON transport for the LAN protocol in
/// `docs/design/remote-control.md`.
class WebSocketRemoteApi implements RemoteApi {
  WebSocketRemoteApi({this.requestTimeout = const Duration(seconds: 25)});

  final Duration requestTimeout;

  final StreamController<RemoteEvent> _events =
      StreamController<RemoteEvent>.broadcast();
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _nextId = 1;
  bool _intentionalClose = false;
  bool _closedSignaled = false;

  @override
  bool get isOpen => _socket?.readyState == WebSocket.open;

  @override
  Stream<RemoteEvent> get events => _events.stream;

  @override
  Future<void> connect(String host, int port) async {
    await _closeSocket(notify: false);
    _intentionalClose = false;
    _closedSignaled = false;

    try {
      final socket = await WebSocket.connect(
        websocketUri(host, port).toString(),
        compression: CompressionOptions.compressionOff,
      ).timeout(const Duration(seconds: 9));
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _subscription = socket.listen(
        _onData,
        onError: (Object error, StackTrace _) {
          _failPending(
            RemoteApiException('socket', 'Socket error: $error', cause: error),
          );
          _signalClosed('$error');
        },
        onDone: () {
          final reason = socket.closeReason;
          final code = socket.closeCode;
          _failPending(
            RemoteApiException(
              'socket',
              reason?.isNotEmpty == true
                  ? reason!
                  : 'Connection closed${code == null ? '' : ' ($code)'}',
            ),
          );
          _signalClosed(reason);
        },
        cancelOnError: false,
      );
    } on TimeoutException catch (error) {
      throw RemoteApiException(
        'timeout',
        'Timed out connecting to $host:$port',
        cause: error,
      );
    } on SocketException catch (error) {
      throw RemoteApiException('socket', error.message, cause: error);
    } on WebSocketException catch (error) {
      throw RemoteApiException('socket', error.message, cause: error);
    }
  }

  @override
  Future<Object?> request(
    String command, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return Future<Object?>.error(
        const RemoteApiException('not_connected', 'Not connected to a studio'),
      );
    }

    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    final message = <String, Object?>{
      'v': 1,
      'id': id,
      'cmd': command,
      ...fields,
    };

    try {
      socket.add(jsonEncode(message));
    } catch (error) {
      _pending.remove(id);
      return Future<Object?>.error(
        RemoteApiException('socket', 'Could not send command: $error'),
      );
    }

    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw RemoteApiException(
          'timeout',
          'The studio did not answer "$command" in time',
        );
      },
    );
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // A malformed frame must not tear down the connection; the next valid
      // response can still be matched by id.
      return;
    }
    if (decoded is! Map) return;
    final message = Map<String, Object?>.from(decoded);

    final id = message['id'];
    if (id is num) {
      _resolve(id.toInt(), message);
      return;
    }

    final event = jsonString(message['event']);
    if (event.isEmpty) return;
    final data = jsonMap(message['data']);

    switch (event) {
      case 'project':
        _events.add(ProjectEvent(RemoteProject.fromJson(data)));
      case 'transport':
        _events.add(
          TransportEvent(
            TransportState.fromJson(data, receivedAtMicros: _nowMicros()),
          ),
        );
      case 'meters':
        final peaks = <int, double>{};
        for (final item in jsonList(data['tracks'])) {
          final map = jsonMap(item);
          peaks[jsonInt(map['id'])] = clampDouble(
            jsonDouble(map['peak']),
            0,
            1,
          );
        }
        final master = jsonList(data['master']);
        _events.add(
          MetersEvent(
            trackPeaks: peaks,
            masterLeft:
                master.isNotEmpty
                    ? clampDouble(jsonDouble(master[0]), 0, 1)
                    : 0,
            masterRight:
                master.length > 1
                    ? clampDouble(jsonDouble(master[1]), 0, 1)
                    : 0,
          ),
        );
    }
  }

  void _resolve(int id, Map<String, Object?> message) {
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (jsonBool(message['ok'])) {
      completer.complete(message['result']);
      return;
    }
    final error = jsonMap(message['error']);
    completer.completeError(
      RemoteApiException(
        jsonString(error['code'], 'unknown'),
        jsonString(error['message'], 'Command failed'),
      ),
    );
  }

  void _failPending(RemoteApiException error) {
    final pending = List<Completer<Object?>>.from(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _signalClosed(String? reason) {
    if (_closedSignaled || _intentionalClose) return;
    _closedSignaled = true;
    _events.add(ConnectionClosedEvent(message: reason));
  }

  Future<void> _closeSocket({required bool notify}) async {
    final socket = _socket;
    _socket = null;
    await _subscription?.cancel();
    _subscription = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure);
      } catch (_) {
        // Already closed.
      }
    }
    if (notify) {
      _failPending(
        const RemoteApiException('not_connected', 'Connection closed'),
      );
      _signalClosed('Connection closed');
    }
  }

  @override
  Future<void> close() async {
    _intentionalClose = true;
    await _closeSocket(notify: true);
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }

  int _nowMicros() => DateTime.now().microsecondsSinceEpoch;
}
