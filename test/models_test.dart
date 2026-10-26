import 'package:ezmusicproduction_remote/core/format.dart';
import 'package:ezmusicproduction_remote/models/project.dart';
import 'package:ezmusicproduction_remote/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteProject', () {
    final project = RemoteProject.fromJson({
      'revision': 12,
      'canUndo': true,
      'canRedo': false,
      'name': 'Demo',
      'sampleRate': 44100,
      'tempoBpm': 128,
      'timeSigNum': 3,
      'timeSigDen': 4,
      'duration': 30,
      'masterGain': 0.8,
      'inputQuantize': 0.25,
      'masterFx': [
        {'index': 0, 'name': 'Limiter', 'bypass': false},
      ],
      'tracks': [
        {
          'id': 7,
          'type': 'instrument',
          'name': 'Keys',
          'colorIndex': 4,
          'volume': 0.75,
          'pan': -0.25,
          'mute': false,
          'solo': true,
          'armed': false,
          'inputChannel': 1,
          'instrument': 'Piano',
          'midiFx': 'Arpeggiator',
          'fx': [
            {'index': 0, 'name': 'Chorus', 'bypass': true},
          ],
          'automation': {
            'volume': [
              {'t': 0, 'v': 0.5},
              {'t': 4, 'v': 1.5},
            ],
            'pan': [],
            'sustain': [],
            'params': [
              {
                'index': 2,
                'slotKind': 0,
                'slotIndex': 0,
                'paramIndex': 3,
                'name': 'Depth',
                'points': [
                  {'time': 1, 'value': 0.25},
                ],
              },
            ],
          },
          'clips': [
            {
              'id': 21,
              'kind': 'midi',
              'start': 2,
              'length': 8,
              'offset': 0,
              'gain': 1,
              'fadeIn': 0.1,
              'fadeOut': 0.2,
              'muted': false,
              'notes': [
                {'pitch': 60, 'velocity': 100, 'start': 0, 'length': 0.5},
              ],
            },
          ],
        },
      ],
    });

    test('parses project, tracks, clips and automation', () {
      expect(project.revision, 12);
      expect(project.name, 'Demo');
      expect(project.masterFx.single.name, 'Limiter');
      expect(project.tracks.single.name, 'Keys');
      expect(project.tracks.single.isInstrument, isTrue);
      expect(project.tracks.single.hasInstrument, isTrue);
      expect(project.tracks.single.fx.single.bypass, isTrue);
      expect(project.tracks.single.clips.single.isMidi, isTrue);
      expect(project.tracks.single.clips.single.notes.single.pitch, 60);
      expect(project.lastClipEnd, 10);
      expect(project.totalClips, 1);
      expect(project.trackForClip(21)?.id, 7);
      expect(project.trackById(7)?.automation.volume.length, 2);
      expect(project.trackById(7)?.automation.params.single.name, 'Depth');
    });

    test('clamps automation values to the normalized range', () {
      final volume = project.tracks.single.automation.volume;
      expect(volume.first.value, 0.5);
      expect(volume.last.value, 1);
    });

    test('sorts automation points by time', () {
      final automation = AutomationSet.fromJson({
        'volume': [
          {'t': 4, 'v': 0.2},
          {'t': 1, 'v': 0.8},
          {'t': 2, 'v': 0.4},
        ],
      });
      expect(
        automation.volume.map((point) => point.time),
        orderedEquals(<double>[1, 2, 4]),
      );
    });

    test('copy helpers replace only the requested data', () {
      final renamed = project.tracks.single.copyWith(name: 'Strings');
      final updated = project.withTrack(renamed);
      expect(updated.trackById(7)?.name, 'Strings');
      expect(updated.revision, project.revision);
      expect(project.withoutTrack(7).tracks, isEmpty);
      expect(project.withMasterGain(8).masterGain, 4);
    });
  });

  test('TransportState parses and reports the running state', () {
    final transport = TransportState.fromJson({
      'playing': true,
      'recording': false,
      'position': 3.5,
      'duration': 120,
      'recordStart': 0,
      'metronome': true,
      'tempoBpm': 100,
      'timeSigNum': 4,
      'timeSigDen': 4,
      'revision': 4,
    }, receivedAtMicros: 1234);

    expect(transport.position, 3.5);
    expect(transport.receivedAtMicros, 1234);
    expect(transport.isRunning, isTrue);
    expect(transport.copyWith(playing: false).isRunning, isFalse);
  });

  test('MeterSnapshot returns silence for unknown tracks', () {
    const snapshot = MeterSnapshot(
      tracks: {3: MeterReading(peak: 0.5, hold: 0.7)},
      masterLeft: MeterReading(peak: 0.4),
      masterRight: MeterReading(peak: 0.3),
      updatedAtMicros: 10,
    );

    expect(snapshot.track(3).peak, 0.5);
    expect(snapshot.track(99).peak, 0);
    expect(snapshot.masterLeft.hold, 0);
  });

  group('format helpers', () {
    test('formats gain, pan and clock values', () {
      expect(formatDb(1), '0.0 dB');
      expect(formatDb(0), '-∞ dB');
      expect(formatPan(0), 'C');
      expect(formatPan(-0.5), 'L50');
      expect(formatPan(0.25), 'R25');
      expect(formatClock(65.25), '1:05.250');
    });

    test('formats bars and beats with safe defaults', () {
      expect(
        formatBarsBeats(2.0, bpm: 120, numerator: 4, denominator: 4),
        '2.1.00',
      );
      expect(
        formatBarsBeats(0.25, bpm: 0, numerator: 0, denominator: 0),
        '1.1.48',
      );
    });
  });
}
