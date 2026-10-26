import 'dart:async';

import 'package:ezmusicproduction_remote/app.dart';
import 'package:ezmusicproduction_remote/data/remote_api.dart';
import 'package:ezmusicproduction_remote/data/settings_store.dart';
import 'package:ezmusicproduction_remote/models/session.dart';
import 'package:ezmusicproduction_remote/state/remote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pair authenticates, installs the snapshot and remembers the studio',
    () async {
      final api = _FakeRemoteApi();
      final store = _MemorySettingsStore();
      final controller = RemoteController(
        apiFactory: () => api,
        settingsStore: store,
        settings: const AppSettings(),
        nowMicros: () => 1000000,
      );

      final ok = await controller.pair(
        host: '192.168.1.20',
        port: 47823,
        token: '123456',
      );

      expect(ok, isTrue);
      expect(controller.connection.value.phase, ConnectionPhase.connected);
      expect(controller.project.value?.name, 'Test Session');
      expect(controller.transport.value.tempoBpm, 120);
      expect(controller.selectedTrackId.value, 1);
      expect(controller.server.value?.projectName, 'Test Session');
      expect(
        api.requests.map((request) => request.$1),
        containsAll(<String>['hello', 'subscribe']),
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.settings.devices.single.host, '192.168.1.20');
      expect(store.saved?.devices.single.token, '123456');

      controller.dispose();
    },
  );

  test(
    'an authentication failure is reported and removes the saved token',
    () async {
      final api = _FakeRemoteApi()..failAuth = true;
      final store = _MemorySettingsStore(
        AppSettings(
          devices: [
            RemoteDevice(
              host: '192.168.1.20',
              port: 47823,
              token: 'wrong',
              projectName: 'Test Session',
              lastUsed: DateTime(2026),
            ),
          ],
        ),
      );
      final controller = RemoteController(
        apiFactory: () => api,
        settingsStore: store,
        settings: store.initial,
      );

      final ok = await controller.pair(
        host: '192.168.1.20',
        port: 47823,
        token: 'wrong',
      );

      expect(ok, isFalse);
      expect(controller.connection.value.phase, ConnectionPhase.authFailed);
      expect(controller.settings.devices, isEmpty);
      controller.dispose();
    },
  );

  test('resuming after an auth failure does not retry the bad token', () async {
    final api = _FakeRemoteApi()..failAuth = true;
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: 'wrong1');
    expect(controller.connection.value.phase, ConnectionPhase.authFailed);

    await controller.onAppResumed();

    expect(
      api.requests.where((request) => request.$1 == 'hello'),
      hasLength(1),
    );
    controller.dispose();
  });

  test(
    'a socket closed during the handshake is not reported as connected',
    () async {
      final api = _FakeRemoteApi()..closeDuringHello = true;
      final controller = RemoteController(
        apiFactory: () => api,
        settingsStore: _MemorySettingsStore(),
        settings: const AppSettings(),
      );

      final ok = await controller.pair(
        host: 'studio.local',
        port: 47823,
        token: '123456',
      );

      expect(ok, isFalse);
      expect(controller.connection.value.phase, ConnectionPhase.error);
      expect(controller.project.value, isNull);
      controller.dispose();
    },
  );

  test(
    'fader previews update immediately and coalesce into one undo entry',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteController(
        apiFactory: () => api,
        settingsStore: _MemorySettingsStore(),
        settings: const AppSettings(),
        nowMicros: () => 1000000,
      );
      await controller.pair(host: 'studio.local', port: 47823, token: '123456');

      controller.previewTrackVolume(1, 0.25);
      expect(controller.project.value?.trackById(1)?.volume, 0.25);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      final previews =
          api.requests
              .where((request) => request.$1 == 'mixer.setTrack')
              .toList();
      expect(previews, hasLength(1));
      expect(previews.single.$2['volume'], 0.25);
      expect(previews.single.$2['undo'], isFalse);

      await controller.commitTrackMix(1, volume: 0.3);
      final commits =
          api.requests
              .where((request) => request.$1 == 'mixer.setTrack')
              .toList();
      expect(commits, hasLength(2));
      expect(commits.last.$2['volume'], 0.3);
      expect(commits.last.$2['undo'], isTrue);

      controller.dispose();
    },
  );

  test('a new session can still coalesce fader previews', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    controller.previewTrackVolume(1, 0.4);
    await Future<void>.delayed(const Duration(milliseconds: 90));

    final previews =
        api.requests
            .where((request) => request.$1 == 'mixer.setTrack')
            .toList();
    expect(previews, hasLength(1));
    expect(previews.single.$2['volume'], 0.4);
    controller.dispose();
  });

  test('master previews are coalesced and committed with undo', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    controller.previewMasterGain(0.5);
    controller.previewMasterGain(0.7);
    expect(controller.project.value?.masterGain, 0.7);
    await Future<void>.delayed(const Duration(milliseconds: 90));

    final previews =
        api.requests
            .where((request) => request.$1 == 'mixer.setMaster')
            .toList();
    expect(previews, hasLength(1));
    expect(previews.single.$2['gain'], 0.7);
    expect(previews.single.$2['undo'], isFalse);

    await controller.commitMasterGain(0.8);
    final commits =
        api.requests
            .where((request) => request.$1 == 'mixer.setMaster')
            .toList();
    expect(commits, hasLength(2));
    expect(commits.last.$2['gain'], 0.8);
    expect(commits.last.$2['undo'], isTrue);
    controller.dispose();
  });

  test(
    'a dropped socket discards stale fader previews before reconnecting',
    () async {
      final api = _FakeRemoteApi();
      final controller = RemoteController(
        apiFactory: () => api,
        settingsStore: _MemorySettingsStore(),
        settings: const AppSettings(),
      );
      await controller.pair(host: 'studio.local', port: 47823, token: '123456');

      controller.previewTrackVolume(1, 0.25);
      expect(controller.project.value?.trackById(1)?.volume, 0.25);

      api.emit(const ConnectionClosedEvent(message: 'Network is unreachable'));
      await controller.reconnectNow();
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(controller.connection.value.phase, ConnectionPhase.connected);
      expect(controller.project.value?.trackById(1)?.volume, 0.8);
      expect(
        api.requests.where((request) => request.$1 == 'mixer.setTrack'),
        isEmpty,
      );
      controller.dispose();
    },
  );

  test('tempo changes update both transport and project state', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await controller.setTempo(140);

    expect(controller.transport.value.tempoBpm, 140);
    expect(controller.project.value?.tempoBpm, 140);
    controller.dispose();
  });

  test('clip commands report failure so sheets can stay open', () async {
    final api = _FakeRemoteApi()..failClipCommands = true;
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    expect(await controller.moveClip(10, 1, 2), isFalse);
    expect(await controller.splitClip(10, 2), isFalse);
    expect(await controller.removeClip(10), isFalse);
    controller.dispose();
  });

  test('meter events are smoothed into the public snapshot', () async {
    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
      nowMicros: () => 1000000,
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    api.emit(
      const MetersEvent(
        trackPeaks: {1: 0.9},
        masterLeft: 0.8,
        masterRight: 0.7,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.meters.value.track(1).peak, 0.9);
    expect(controller.meters.value.masterLeft.peak, 0.8);
    expect(controller.meters.value.masterRight.peak, 0.7);
    controller.dispose();
  });

  test('the playhead interpolates between transport packets', () async {
    var now = 1000000;
    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(),
      nowMicros: () => now,
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    controller.transport.value = controller.transport.value.copyWith(
      playing: true,
      position: 2,
      receivedAtMicros: 1000000,
    );
    now = 2000000;

    expect(controller.estimatedPosition, closeTo(3, 0.001));
    controller.dispose();
  });

  testWidgets('the workspace renders all four destinations', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Test Session'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Mixer'), findsOneWidget);

    await tester.tap(find.text('Mixer'));
    await tester.pumpAndSettle();
    expect(find.text('Drums'), findsWidgets);

    await tester.tap(find.text('Effects'));
    await tester.pumpAndSettle();
    expect(find.text('Effects'), findsWidgets);

    await tester.tap(find.text('Automation'));
    await tester.pumpAndSettle();
    expect(find.text('Automation'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('the phone workspace fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Test Session'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'rendering Timeline');

    for (final destination in <String>['Mixer', 'Effects', 'Automation']) {
      await tester.tap(find.text(destination).first);
      await tester.pumpAndSettle();
      expect(find.text(destination), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'rendering $destination');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('phone sheets render on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();

    Future<void> dismissSheet() async {
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
    await dismissSheet();

    await tester.tap(find.byTooltip('Add track').first);
    await tester.pumpAndSettle();
    expect(find.text('Add track'), findsWidgets);
    expect(tester.takeException(), isNull);
    await dismissSheet();

    await tester.longPress(find.text('Drums').first);
    await tester.pumpAndSettle();
    expect(find.text('Drums'), findsWidgets);
    expect(tester.takeException(), isNull);
    await dismissSheet();

    await tester.longPress(find.byKey(const ValueKey('clip-10')));
    await tester.pumpAndSettle();
    expect(find.text('Audio clip'), findsWidgets);
    expect(tester.takeException(), isNull);
    await dismissSheet();

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('timeline taps use content coordinates after scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();

    final grid = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_GridPainter',
    );
    expect(grid, findsOneWidget);

    ScrollableState? horizontal;
    final scrollables = find.ancestor(
      of: grid,
      matching: find.byType(Scrollable),
    );
    for (final element in scrollables.evaluate()) {
      final scrollable = element.widget as Scrollable;
      if (scrollable.axisDirection == AxisDirection.right) {
        horizontal = (element as StatefulElement).state as ScrollableState;
        break;
      }
    }
    expect(horizontal, isNotNull);
    horizontal!.position.jumpTo(300);
    await tester.pumpAndSettle();

    // The tap is 100 px into the viewport after a 300 px scroll. Its content
    // coordinate is therefore 400 px, not 700 px.
    final rect = tester.getRect(grid);
    await tester.tapAt(Offset(rect.left + 400, rect.top + 50));
    await tester.pump();

    final seek = api.requests.lastWhere(
      (request) => request.$1 == 'transport.seek',
    );
    expect(seek.$2['seconds'], closeTo(400 / 42, 0.2));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a landscape phone renders every destination', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'rendering Timeline');

    for (final destination in <String>['Mixer', 'Effects', 'Automation']) {
      await tester.tap(find.text(destination).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'rendering $destination');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('a landscape tablet uses the rail without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'rendering Timeline');

    for (final destination in <String>['Mixer', 'Effects', 'Automation']) {
      await tester.tap(find.text(destination).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'rendering $destination');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('the wide workspace uses the navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeRemoteApi();
    final controller = RemoteController(
      apiFactory: () => api,
      settingsStore: _MemorySettingsStore(),
      settings: const AppSettings(autoReconnect: false),
    );
    await controller.pair(host: 'studio.local', port: 47823, token: '123456');

    await tester.pumpWidget(RemoteApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Test Session'), findsOneWidget);

    await tester.tap(find.text('Effects').first);
    await tester.pumpAndSettle();
    expect(find.text('Effects'), findsWidgets);

    await tester.tap(find.text('Automation').first);
    await tester.pumpAndSettle();
    expect(find.text('Automation'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _FakeRemoteApi implements RemoteApi {
  final StreamController<RemoteEvent> _events =
      StreamController<RemoteEvent>.broadcast();
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  bool failAuth = false;
  bool failClipCommands = false;
  bool closeDuringHello = false;
  bool _open = false;
  int _revision = 1;

  @override
  bool get isOpen => _open;

  @override
  Stream<RemoteEvent> get events => _events.stream;

  @override
  Future<void> connect(String host, int port) async {
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  void emit(RemoteEvent event) => _events.add(event);

  @override
  Future<Object?> request(
    String command, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) async {
    requests.add((command, Map<String, Object?>.of(fields)));
    switch (command) {
      case 'hello':
        if (failAuth) {
          throw const RemoteApiException('auth_failed', 'Invalid pairing code');
        }
        if (closeDuringHello) {
          _open = false;
          _events.add(
            const ConnectionClosedEvent(message: 'closed after hello'),
          );
        }
        return <String, Object?>{
          'protocol': 1,
          'clientId': 1,
          'server': <String, Object?>{
            'app': 'EZMusicProduction',
            'port': 47823,
            'requiresToken': true,
            'protocol': 1,
            'projectName': 'Test Session',
            'capabilities': <String>['transport', 'mixer', 'meters'],
          },
          'state': _state(),
          'transport': _transport(),
        };
      case 'subscribe':
        return <String, Object?>{'meters': true, 'metersHz': 20};
      case 'state.get':
        return <String, Object?>{'state': _state(), 'transport': _transport()};
      case 'transport.play':
        return <String, Object?>{'playing': true};
      case 'transport.pause':
        return <String, Object?>{'playing': false};
      case 'transport.stop':
        return <String, Object?>{'playing': false, 'position': 0};
      case 'transport.seek':
        return <String, Object?>{'position': fields['seconds'] ?? 0};
      case 'transport.tempo':
        return <String, Object?>{
          'tempoBpm': fields['bpm'],
          'revision': ++_revision,
        };
      case 'mixer.setTrack':
        return <String, Object?>{
          'trackId': fields['trackId'],
          'revision': ++_revision,
        };
      case 'clip.move':
      case 'clip.split':
      case 'clip.remove':
        if (failClipCommands) {
          throw const RemoteApiException('not_found', 'Clip not found');
        }
        return <String, Object?>{'revision': ++_revision};
      default:
        return <String, Object?>{'revision': ++_revision};
    }
  }

  Map<String, Object?> _state() => <String, Object?>{
    'revision': _revision,
    'canUndo': true,
    'canRedo': false,
    'name': 'Test Session',
    'sampleRate': 48000.0,
    'tempoBpm': 120.0,
    'timeSigNum': 4,
    'timeSigDen': 4,
    'duration': 64.0,
    'masterGain': 1.0,
    'inputQuantize': 0.0,
    'masterFx': <Object?>[],
    'tracks': <Object?>[
      <String, Object?>{
        'id': 1,
        'type': 'audio',
        'name': 'Drums',
        'colorIndex': 0,
        'volume': 0.8,
        'pan': 0.0,
        'mute': false,
        'solo': false,
        'armed': false,
        'inputChannel': 0,
        'instrument': '',
        'midiFx': '',
        'fx': <Object?>[],
        'automation': <String, Object?>{
          'volume': <Object?>[],
          'pan': <Object?>[],
          'sustain': <Object?>[],
          'params': <Object?>[],
        },
        'clips': <Object?>[
          <String, Object?>{
            'id': 10,
            'kind': 'audio',
            'start': 1.0,
            'length': 4.0,
            'offset': 0.0,
            'gain': 1.0,
            'fadeIn': 0.0,
            'fadeOut': 0.0,
            'muted': false,
            'notes': <Object?>[],
          },
        ],
      },
    ],
  };

  Map<String, Object?> _transport() => <String, Object?>{
    'playing': false,
    'recording': false,
    'position': 0.0,
    'duration': 64.0,
    'recordStart': 0.0,
    'metronome': false,
    'tempoBpm': 120.0,
    'timeSigNum': 4,
    'timeSigDen': 4,
    'revision': _revision,
  };
}

class _MemorySettingsStore implements SettingsStore {
  _MemorySettingsStore([this.initial = const AppSettings()]);

  final AppSettings initial;
  AppSettings? saved;

  @override
  Future<AppSettings> load() async => initial;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
  }
}
