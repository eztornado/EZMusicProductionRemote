import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ezmusicproduction_remote/data/remote_api.dart';
import 'package:ezmusicproduction_remote/data/websocket_remote_api.dart';
import 'package:ezmusicproduction_remote/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WebSocketRemoteApi matches responses and decodes push events',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final serverSubscription = server.listen((request) {
        unawaited(_serve(request, sockets));
      });

      final api = WebSocketRemoteApi(
        requestTimeout: const Duration(seconds: 2),
      );
      final events = <RemoteEvent>[];
      final eventsSubscription = api.events.listen(events.add);

      try {
        await api.connect(InternetAddress.loopbackIPv4.address, server.port);

        final hello = await api.request('hello', <String, Object?>{
          'token': '123456',
        });
        expect((hello as Map<String, Object?>)['protocol'], 1);

        final echo = await api.request('ping');
        expect((echo as Map<String, Object?>)['echo'], 'ping');

        await expectLater(
          api.request('missing'),
          throwsA(
            isA<RemoteApiException>()
                .having((error) => error.code, 'code', 'not_found')
                .having((error) => error.message, 'message', 'No such thing'),
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(events.whereType<ProjectEvent>(), hasLength(1));
        expect(
          events.whereType<ProjectEvent>().single.project.name,
          'Integration Session',
        );
        expect(events.whereType<TransportEvent>(), hasLength(1));
        expect(
          events.whereType<TransportEvent>().single.transport.position,
          3.5,
        );
        expect(events.whereType<MetersEvent>(), hasLength(1));
        final meters = events.whereType<MetersEvent>().single;
        expect(meters.trackPeaks[3], 0.42);
        expect(meters.masterLeft, 0.51);
        expect(meters.masterRight, 0.49);
      } finally {
        await eventsSubscription.cancel();
        await api.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
        await serverSubscription.cancel();
      }
    },
  );
}

Future<void> _serve(HttpRequest request, List<WebSocket> sockets) async {
  final socket = await WebSocketTransformer.upgrade(request);
  sockets.add(socket);
  socket.listen((raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw) as Map<String, Object?>;
    final id = message['id'];
    switch (message['cmd']) {
      case 'hello':
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'id': id,
            'ok': true,
            'result': <String, Object?>{
              'protocol': 1,
              'clientId': 7,
              'server': <String, Object?>{
                'app': 'EZMusicProduction',
                'port': 47823,
                'requiresToken': true,
                'protocol': 1,
                'projectName': 'Integration Session',
                'capabilities': <String>['transport', 'mixer', 'meters'],
              },
              'state': <String, Object?>{
                'revision': 4,
                'canUndo': false,
                'canRedo': false,
                'name': 'Integration Session',
                'sampleRate': 48000.0,
                'tempoBpm': 120.0,
                'timeSigNum': 4,
                'timeSigDen': 4,
                'duration': 12.0,
                'masterGain': 1.0,
                'inputQuantize': 0.0,
                'masterFx': <Object?>[],
                'tracks': <Object?>[],
              },
              'transport': <String, Object?>{
                'playing': false,
                'recording': false,
                'position': 0.0,
                'duration': 12.0,
                'recordStart': 0.0,
                'metronome': false,
                'tempoBpm': 120.0,
                'timeSigNum': 4,
                'timeSigDen': 4,
                'revision': 4,
              },
            },
          }),
        );
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'event': 'project',
            'data': <String, Object?>{
              'revision': 5,
              'canUndo': true,
              'canRedo': false,
              'name': 'Integration Session',
              'sampleRate': 48000.0,
              'tempoBpm': 120.0,
              'timeSigNum': 4,
              'timeSigDen': 4,
              'duration': 12.0,
              'masterGain': 1.0,
              'inputQuantize': 0.0,
              'masterFx': <Object?>[],
              'tracks': <Object?>[],
            },
          }),
        );
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'event': 'transport',
            'data': <String, Object?>{
              'playing': true,
              'recording': false,
              'position': 3.5,
              'duration': 12.0,
              'recordStart': 0.0,
              'metronome': true,
              'tempoBpm': 120.0,
              'timeSigNum': 4,
              'timeSigDen': 4,
              'revision': 5,
            },
          }),
        );
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'event': 'meters',
            'data': <String, Object?>{
              'tracks': <Object?>[
                <String, Object?>{'id': 3, 'peak': 0.42},
              ],
              'master': <Object?>[0.51, 0.49],
            },
          }),
        );
      case 'missing':
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'id': id,
            'ok': false,
            'error': <String, Object?>{
              'code': 'not_found',
              'message': 'No such thing',
            },
          }),
        );
      default:
        socket.add(
          jsonEncode(<String, Object?>{
            'v': 1,
            'id': id,
            'ok': true,
            'result': <String, Object?>{'echo': message['cmd']},
          }),
        );
    }
  });
}
