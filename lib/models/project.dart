import '../core/json.dart';

/// Immutable snapshot of the DAW project, mirroring the JSON in §7 of
/// `docs/design/remote-control.md`.
class RemoteProject {
  const RemoteProject({
    required this.revision,
    required this.canUndo,
    required this.canRedo,
    required this.name,
    required this.sampleRate,
    required this.tempoBpm,
    required this.timeSigNum,
    required this.timeSigDen,
    required this.duration,
    required this.masterGain,
    required this.inputQuantize,
    required this.masterFx,
    required this.tracks,
  });

  factory RemoteProject.fromJson(Map<String, Object?> json) {
    return RemoteProject(
      revision: jsonInt(json['revision']),
      canUndo: jsonBool(json['canUndo']),
      canRedo: jsonBool(json['canRedo']),
      name: jsonString(json['name'], 'Untitled'),
      sampleRate: jsonDouble(json['sampleRate'], 48000),
      tempoBpm: jsonDouble(json['tempoBpm'], 120),
      timeSigNum: jsonInt(json['timeSigNum'], 4),
      timeSigDen: jsonInt(json['timeSigDen'], 4),
      duration: jsonDouble(json['duration']),
      masterGain: jsonDouble(json['masterGain'], 1),
      inputQuantize: jsonDouble(json['inputQuantize']),
      masterFx: jsonList(
        json['masterFx'],
      ).map((item) => FxSlot.fromJson(jsonMap(item))).toList(growable: false),
      tracks: jsonList(json['tracks'])
          .map((item) => RemoteTrack.fromJson(jsonMap(item)))
          .toList(growable: false),
    );
  }

  final int revision;
  final bool canUndo;
  final bool canRedo;
  final String name;
  final double sampleRate;
  final double tempoBpm;
  final int timeSigNum;
  final int timeSigDen;
  final double duration;
  final double masterGain;
  final double inputQuantize;
  final List<FxSlot> masterFx;
  final List<RemoteTrack> tracks;

  RemoteTrack? trackById(int? id) {
    if (id == null) return null;
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  RemoteClip? clipById(int? id) {
    if (id == null) return null;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == id) return clip;
      }
    }
    return null;
  }

  RemoteTrack? trackForClip(int? clipId) {
    if (clipId == null) return null;
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return track;
      }
    }
    return null;
  }

  /// Last moment occupied by a clip, used to size the timeline.
  double get lastClipEnd {
    var end = 0.0;
    for (final track in tracks) {
      for (final clip in track.clips) {
        final clipEnd = clip.start + clip.length;
        if (clipEnd > end) end = clipEnd;
      }
    }
    return end;
  }

  int get totalClips =>
      tracks.fold<int>(0, (sum, track) => sum + track.clips.length);

  RemoteProject copyWith({
    int? revision,
    bool? canUndo,
    bool? canRedo,
    String? name,
    double? sampleRate,
    double? tempoBpm,
    int? timeSigNum,
    int? timeSigDen,
    double? duration,
    double? masterGain,
    double? inputQuantize,
    List<FxSlot>? masterFx,
    List<RemoteTrack>? tracks,
  }) {
    return RemoteProject(
      revision: revision ?? this.revision,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      name: name ?? this.name,
      sampleRate: sampleRate ?? this.sampleRate,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      timeSigNum: timeSigNum ?? this.timeSigNum,
      timeSigDen: timeSigDen ?? this.timeSigDen,
      duration: duration ?? this.duration,
      masterGain: masterGain ?? this.masterGain,
      inputQuantize: inputQuantize ?? this.inputQuantize,
      masterFx: masterFx ?? this.masterFx,
      tracks: tracks ?? this.tracks,
    );
  }

  RemoteProject withTrack(RemoteTrack updated) {
    return copyWith(
      tracks: tracks
          .map((track) => track.id == updated.id ? updated : track)
          .toList(growable: false),
    );
  }

  RemoteProject withoutTrack(int trackId) {
    return copyWith(
      tracks: tracks
          .where((track) => track.id != trackId)
          .toList(growable: false),
    );
  }

  RemoteProject withMasterGain(double gain) {
    return copyWith(masterGain: clampDouble(gain, 0, 4));
  }
}

class RemoteTrack {
  const RemoteTrack({
    required this.id,
    required this.type,
    required this.name,
    required this.colorIndex,
    required this.volume,
    required this.pan,
    required this.mute,
    required this.solo,
    required this.armed,
    required this.inputChannel,
    required this.instrument,
    required this.midiFx,
    required this.fx,
    required this.automation,
    required this.clips,
  });

  factory RemoteTrack.fromJson(Map<String, Object?> json) {
    return RemoteTrack(
      id: jsonInt(json['id']),
      type: jsonString(json['type'], 'audio'),
      name: jsonString(json['name'], 'Track'),
      colorIndex: jsonInt(json['colorIndex']),
      volume: jsonDouble(json['volume'], 1),
      pan: jsonDouble(json['pan']),
      mute: jsonBool(json['mute']),
      solo: jsonBool(json['solo']),
      armed: jsonBool(json['armed']),
      inputChannel: jsonInt(json['inputChannel']),
      instrument: jsonString(json['instrument']),
      midiFx: jsonString(json['midiFx']),
      fx: jsonList(
        json['fx'],
      ).map((item) => FxSlot.fromJson(jsonMap(item))).toList(growable: false),
      automation: AutomationSet.fromJson(jsonMap(json['automation'])),
      clips: jsonList(json['clips'])
          .map((item) => RemoteClip.fromJson(jsonMap(item)))
          .toList(growable: false),
    );
  }

  final int id;
  final String type;
  final String name;
  final int colorIndex;
  final double volume;
  final double pan;
  final bool mute;
  final bool solo;
  final bool armed;
  final int inputChannel;
  final String instrument;
  final String midiFx;
  final List<FxSlot> fx;
  final AutomationSet automation;
  final List<RemoteClip> clips;

  bool get isInstrument => type == 'instrument';
  bool get hasInstrument => instrument.trim().isNotEmpty;
  bool get hasMidiFx => midiFx.trim().isNotEmpty;

  RemoteTrack copyWith({
    int? id,
    String? type,
    String? name,
    int? colorIndex,
    double? volume,
    double? pan,
    bool? mute,
    bool? solo,
    bool? armed,
    int? inputChannel,
    String? instrument,
    String? midiFx,
    List<FxSlot>? fx,
    AutomationSet? automation,
    List<RemoteClip>? clips,
  }) {
    return RemoteTrack(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      colorIndex: colorIndex ?? this.colorIndex,
      volume: volume ?? this.volume,
      pan: pan ?? this.pan,
      mute: mute ?? this.mute,
      solo: solo ?? this.solo,
      armed: armed ?? this.armed,
      inputChannel: inputChannel ?? this.inputChannel,
      instrument: instrument ?? this.instrument,
      midiFx: midiFx ?? this.midiFx,
      fx: fx ?? this.fx,
      automation: automation ?? this.automation,
      clips: clips ?? this.clips,
    );
  }
}

class RemoteClip {
  const RemoteClip({
    required this.id,
    required this.kind,
    required this.start,
    required this.length,
    required this.offset,
    required this.gain,
    required this.fadeIn,
    required this.fadeOut,
    required this.muted,
    required this.notes,
  });

  factory RemoteClip.fromJson(Map<String, Object?> json) {
    return RemoteClip(
      id: jsonInt(json['id']),
      kind: jsonString(json['kind'], 'audio'),
      start: jsonDouble(json['start']),
      length: jsonDouble(json['length']),
      offset: jsonDouble(json['offset']),
      gain: jsonDouble(json['gain'], 1),
      fadeIn: jsonDouble(json['fadeIn']),
      fadeOut: jsonDouble(json['fadeOut']),
      muted: jsonBool(json['muted']),
      notes: jsonList(
        json['notes'],
      ).map((item) => MidiNote.fromJson(jsonMap(item))).toList(growable: false),
    );
  }

  final int id;
  final String kind;
  final double start;
  final double length;
  final double offset;
  final double gain;
  final double fadeIn;
  final double fadeOut;
  final bool muted;
  final List<MidiNote> notes;

  bool get isMidi => kind == 'midi';
  double get end => start + length;

  RemoteClip copyWith({
    int? id,
    String? kind,
    double? start,
    double? length,
    double? offset,
    double? gain,
    double? fadeIn,
    double? fadeOut,
    bool? muted,
    List<MidiNote>? notes,
  }) {
    return RemoteClip(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      start: start ?? this.start,
      length: length ?? this.length,
      offset: offset ?? this.offset,
      gain: gain ?? this.gain,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      muted: muted ?? this.muted,
      notes: notes ?? this.notes,
    );
  }
}

class MidiNote {
  const MidiNote({
    required this.pitch,
    required this.velocity,
    required this.start,
    required this.length,
    this.origStart,
  });

  factory MidiNote.fromJson(Map<String, Object?> json) {
    return MidiNote(
      pitch: jsonInt(json['pitch']),
      velocity: jsonDouble(json['velocity'], 0.8),
      start: jsonDouble(json['start']),
      length: jsonDouble(json['length'], 0.25),
      origStart:
          json.containsKey('origStart') ? jsonDouble(json['origStart']) : null,
    );
  }

  final int pitch; // 0..127
  final double velocity; // 0..1
  final double start; // relative to the clip start
  final double length;
  final double? origStart;
}

class FxSlot {
  const FxSlot({required this.index, required this.name, required this.bypass});

  factory FxSlot.fromJson(Map<String, Object?> json) {
    return FxSlot(
      index: jsonInt(json['index']),
      name: jsonString(json['name'], 'Effect'),
      bypass: jsonBool(json['bypass']),
    );
  }

  final int index;
  final String name;
  final bool bypass;

  FxSlot copyWith({int? index, String? name, bool? bypass}) {
    return FxSlot(
      index: index ?? this.index,
      name: name ?? this.name,
      bypass: bypass ?? this.bypass,
    );
  }
}

class AutomationPoint {
  const AutomationPoint({required this.time, required this.value});

  factory AutomationPoint.fromJson(Map<String, Object?> json) {
    return AutomationPoint(
      time: jsonDouble(json['t'], jsonDouble(json['time'])),
      value: clampDouble(
        jsonDouble(json['v'], jsonDouble(json['value'])),
        0,
        1,
      ),
    );
  }

  final double time; // seconds on the timeline
  final double value; // normalized 0..1

  AutomationPoint copyWith({double? time, double? value}) {
    return AutomationPoint(time: time ?? this.time, value: value ?? this.value);
  }

  Map<String, Object?> toJson() => {'t': time, 'v': value};
}

class AutomationSet {
  const AutomationSet({
    required this.volume,
    required this.pan,
    required this.sustain,
    required this.params,
  });

  factory AutomationSet.fromJson(Map<String, Object?> json) {
    return AutomationSet(
      volume: _points(json['volume']),
      pan: _points(json['pan']),
      sustain: _points(json['sustain']),
      params: jsonList(json['params'])
          .map((item) => ParameterLane.fromJson(jsonMap(item)))
          .toList(growable: false),
    );
  }

  static List<AutomationPoint> _points(Object? raw) {
    final points =
        jsonList(
          raw,
        ).map((item) => AutomationPoint.fromJson(jsonMap(item))).toList();
    points.sort((a, b) => a.time.compareTo(b.time));
    return List<AutomationPoint>.unmodifiable(points);
  }

  static const empty = AutomationSet(
    volume: <AutomationPoint>[],
    pan: <AutomationPoint>[],
    sustain: <AutomationPoint>[],
    params: <ParameterLane>[],
  );

  final List<AutomationPoint> volume;
  final List<AutomationPoint> pan;
  final List<AutomationPoint> sustain;
  final List<ParameterLane> params;

  bool get isEmpty =>
      volume.isEmpty &&
      pan.isEmpty &&
      sustain.isEmpty &&
      params.every((lane) => lane.points.isEmpty);
}

class ParameterLane {
  const ParameterLane({
    required this.index,
    required this.slotKind,
    required this.slotIndex,
    required this.paramIndex,
    required this.name,
    required this.points,
  });

  factory ParameterLane.fromJson(Map<String, Object?> json) {
    return ParameterLane(
      index: jsonInt(json['index']),
      slotKind: jsonInt(json['slotKind']),
      slotIndex: jsonInt(json['slotIndex']),
      paramIndex: jsonInt(json['paramIndex']),
      name: jsonString(json['name'], 'Parameter'),
      points: AutomationSet._points(json['points']),
    );
  }

  final int index;
  final int slotKind;
  final int slotIndex;
  final int paramIndex;
  final String name;
  final List<AutomationPoint> points;

  ParameterLane copyWith({
    int? index,
    int? slotKind,
    int? slotIndex,
    int? paramIndex,
    String? name,
    List<AutomationPoint>? points,
  }) {
    return ParameterLane(
      index: index ?? this.index,
      slotKind: slotKind ?? this.slotKind,
      slotIndex: slotIndex ?? this.slotIndex,
      paramIndex: paramIndex ?? this.paramIndex,
      name: name ?? this.name,
      points: points ?? this.points,
    );
  }
}
