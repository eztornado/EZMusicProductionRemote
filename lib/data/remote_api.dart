import '../models/project.dart';
import '../models/session.dart';

/// Sealed event stream emitted by a remote transport.
sealed class RemoteEvent {
  const RemoteEvent();
}

class ProjectEvent extends RemoteEvent {
  const ProjectEvent(this.project);
  final RemoteProject project;
}

class TransportEvent extends RemoteEvent {
  const TransportEvent(this.transport);
  final TransportState transport;
}

class MetersEvent extends RemoteEvent {
  const MetersEvent({
    required this.trackPeaks,
    required this.masterLeft,
    required this.masterRight,
  });

  final Map<int, double> trackPeaks;
  final double masterLeft;
  final double masterRight;
}

class ConnectionClosedEvent extends RemoteEvent {
  const ConnectionClosedEvent({this.message});

  final String? message;
}

/// Transport-agnostic protocol client. Tests use this interface with an
/// in-memory fake; the app uses [WebSocketRemoteApi].
abstract interface class RemoteApi {
  bool get isOpen;

  Future<void> connect(String host, int port);

  /// Sends one §5 request and resolves with the `result` value. Throws a
  /// [RemoteApiException] for protocol errors, timeouts and socket failures.
  Future<Object?> request(
    String command, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]);

  Stream<RemoteEvent> get events;

  Future<void> close();
}

typedef RemoteApiFactory = RemoteApi Function();
