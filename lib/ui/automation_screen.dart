import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playhead_builder.dart';
import 'sheets/parameter_picker_sheet.dart';

const int _laneVolume = 0;
const int _lanePan = 1;
const int _laneSustain = 2;
const int _laneParameter = 3;

/// Full-height automation editor with tap-to-add, drag-to-shape and
/// long-press-to-delete points. Values are normalized 0..1, matching the
/// protocol, and are only formatted as dB/pan/percent for display.
class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  final ScrollController _horizontal = ScrollController();

  int _laneKind = _laneVolume;
  int? _paramLaneIndex;
  bool _writeMode = false;
  bool _dirty = false;
  List<AutomationPoint> _points = const <AutomationPoint>[];
  int? _dragIndex;
  int _editGeneration = 0;
  double _pixelsPerSecond = 54;
  double _lastViewportWidth = 600;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.selectedTrackId.addListener(_onTrackChanged);
  }

  @override
  void dispose() {
    _controller.selectedTrackId.removeListener(_onTrackChanged);
    _horizontal.dispose();
    super.dispose();
  }

  void _onTrackChanged() {
    if (!mounted) return;
    setState(() {
      _laneKind = _laneVolume;
      _paramLaneIndex = null;
      _writeMode = false;
      _dirty = false;
      _dragIndex = null;
      _editGeneration++;
    });
  }

  ParameterLane? _paramLaneFor(RemoteTrack track) {
    final index = _paramLaneIndex;
    if (index == null) return null;
    for (final lane in track.automation.params) {
      if (lane.index == index) return lane;
    }
    return null;
  }

  List<AutomationPoint> _lanePoints(
    RemoteTrack track,
    int laneKind,
    ParameterLane? paramLane,
  ) {
    switch (laneKind) {
      case _laneVolume:
        return track.automation.volume;
      case _lanePan:
        return track.automation.pan;
      case _laneSustain:
        return track.automation.sustain;
      default:
        return paramLane?.points ?? const <AutomationPoint>[];
    }
  }

  String _laneLabel(L10n l10n, int laneKind, ParameterLane? paramLane) {
    switch (laneKind) {
      case _laneVolume:
        return l10n.t('volumeLane');
      case _lanePan:
        return l10n.t('panLane');
      case _laneSustain:
        return l10n.t('sustainLane');
      default:
        return paramLane?.name ?? l10n.t('parameterLaneTitle');
    }
  }

  String _laneValueLabel(int laneKind, double value) {
    switch (laneKind) {
      case _laneVolume:
        return formatDb(value);
      case _lanePan:
        return formatPan(value * 2 - 1);
      default:
        return '${(value * 100).round()}%';
    }
  }

  double _staticValue(RemoteTrack track, int laneKind) {
    switch (laneKind) {
      case _laneVolume:
        return track.volume.clamp(0.0, 1.0).toDouble();
      case _lanePan:
        return ((track.pan + 1) / 2).clamp(0.0, 1.0).toDouble();
      case _laneSustain:
        return 0;
      default:
        return 0.5;
    }
  }

  double _contentSeconds(RemoteProject project) {
    final end = math.max(project.duration, project.lastClipEnd);
    final bar = barSeconds(
      project.tempoBpm,
      project.timeSigNum,
      project.timeSigDen,
    );
    final raw = math.max(end + 4, bar * 8);
    return (raw / bar).ceil() * bar;
  }

  void _zoomBy(double factor) {
    final next = (_pixelsPerSecond * factor).clamp(8.0, 240.0);
    if (next == _pixelsPerSecond) return;
    setState(() => _pixelsPerSecond = next);
  }

  void _fit(RemoteProject project) {
    final seconds = _contentSeconds(project);
    final viewport = math.max(160.0, _lastViewportWidth - 20);
    final next = (viewport / seconds).clamp(8.0, 220.0);
    setState(() => _pixelsPerSecond = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontal.hasClients) _horizontal.jumpTo(0);
    });
  }

  void _selectLane(int kind, [int? paramIndex]) {
    setState(() {
      _laneKind = kind;
      _paramLaneIndex = kind == _laneParameter ? paramIndex : null;
      _dirty = false;
      _dragIndex = null;
      _editGeneration++;
      if (kind != _laneVolume) _writeMode = false;
    });
  }

  void _toggleWrite() {
    setState(() {
      _writeMode = !_writeMode;
      if (_writeMode) {
        _laneKind = _laneVolume;
        _paramLaneIndex = null;
        _dirty = false;
        _dragIndex = null;
        _editGeneration++;
      }
    });
  }

  Future<void> _addParamLane(RemoteTrack track) async {
    final choice = await showParameterPicker(
      context,
      controller: _controller,
      track: track,
    );
    if (choice == null || !mounted) return;
    for (final lane in track.automation.params) {
      if (lane.slotKind == choice.slotKind &&
          lane.slotIndex == choice.slotIndex &&
          lane.paramIndex == choice.paramIndex) {
        _selectLane(_laneParameter, lane.index);
        return;
      }
    }
    await _controller.setParamAutomation(
      trackId: track.id,
      slotKind: choice.slotKind,
      slotIndex: choice.slotIndex,
      paramIndex: choice.paramIndex,
      name: choice.name,
      points: const <AutomationPoint>[],
    );
    await _controller.refreshState();
    if (!mounted) return;
    final updated = _controller.currentProject?.trackById(track.id);
    if (updated != null) {
      for (final lane in updated.automation.params) {
        if (lane.slotKind == choice.slotKind &&
            lane.slotIndex == choice.slotIndex &&
            lane.paramIndex == choice.paramIndex) {
          _selectLane(_laneParameter, lane.index);
          return;
        }
      }
    }
  }

  Future<void> _clearLane(
    RemoteTrack track,
    int laneKind,
    ParameterLane? paramLane,
    List<AutomationPoint> points,
  ) async {
    if (points.isEmpty) return;
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('clearLane'),
      message: l10n.t('clearLaneConfirm'),
      confirmLabel: l10n.t('clearLane'),
      danger: true,
      icon: Icons.delete_sweep_rounded,
    );
    if (!ok || !mounted) return;
    final next = const <AutomationPoint>[];
    setState(() {
      _points = next;
      _dirty = true;
      _dragIndex = null;
      _editGeneration++;
    });
    await _commitPoints(track, laneKind, paramLane, next, _editGeneration);
  }

  Future<void> _deleteLane(RemoteTrack track, ParameterLane? paramLane) async {
    if (paramLane == null) return;
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('deleteLane'),
      message: l10n.t('deleteLaneConfirm', {'name': paramLane.name}),
      confirmLabel: l10n.t('delete'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await _controller.removeParamLane(track.id, paramLane.index);
    await _controller.refreshState();
    if (!mounted) return;
    setState(() {
      _laneKind = _laneVolume;
      _paramLaneIndex = null;
      _writeMode = false;
      _dirty = false;
      _dragIndex = null;
      _editGeneration++;
    });
  }

  Future<void> _writeAtPlayhead(RemoteTrack track) async {
    final position = _controller.estimatedPosition;
    final value = track.volume.clamp(0.0, 1.0).toDouble();
    await _controller.writeVolumeAutomation(track.id, position, value);
    await _controller.refreshState();
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _laneKind = _laneVolume;
      _paramLaneIndex = null;
      _dragIndex = null;
      _editGeneration++;
    });
  }

  void _addPoint(
    RemoteTrack track,
    int laneKind,
    ParameterLane? paramLane,
    List<AutomationPoint> points,
    double time,
    double value,
  ) {
    final next = List<AutomationPoint>.of(points);
    final existing = next.indexWhere(
      (point) => (point.time - time).abs() < 0.005,
    );
    final point = AutomationPoint(time: time, value: value);
    if (existing >= 0) {
      next[existing] = point;
    } else {
      next.add(point);
    }
    next.sort((a, b) => a.time.compareTo(b.time));
    setState(() {
      _points = next;
      _dirty = true;
      _dragIndex = null;
      _editGeneration++;
    });
    unawaited(_commitPoints(track, laneKind, paramLane, next, _editGeneration));
  }

  void _beginDrag(int index, List<AutomationPoint> points) {
    if (index < 0 || index >= points.length) return;
    setState(() {
      _points = List<AutomationPoint>.of(points);
      _dirty = true;
      _dragIndex = index;
      _editGeneration++;
    });
  }

  void _updateDrag(
    int index,
    Offset delta,
    double editorHeight,
    double duration,
  ) {
    if (_dragIndex != index || index < 0 || index >= _points.length) return;
    final point = _points[index];
    final nextTime =
        (point.time + delta.dx / _pixelsPerSecond)
            .clamp(0.0, duration)
            .toDouble();
    final nextValue = (point.value - delta.dy / math.max(1.0, editorHeight))
        .clamp(0.0, 1.0);
    final next = List<AutomationPoint>.of(_points);
    next[index] = AutomationPoint(time: nextTime, value: nextValue);
    setState(() => _points = next);
  }

  void _endDrag(RemoteTrack track, int laneKind, ParameterLane? paramLane) {
    if (_dragIndex == null) return;
    final next = List<AutomationPoint>.of(_points)
      ..sort((a, b) => a.time.compareTo(b.time));
    setState(() {
      _points = next;
      _dragIndex = null;
      _editGeneration++;
    });
    unawaited(_commitPoints(track, laneKind, paramLane, next, _editGeneration));
  }

  void _deletePoint(
    RemoteTrack track,
    int laneKind,
    ParameterLane? paramLane,
    List<AutomationPoint> points,
    int index,
  ) {
    if (index < 0 || index >= points.length) return;
    final next = List<AutomationPoint>.of(points)..removeAt(index);
    setState(() {
      _points = next;
      _dirty = true;
      _dragIndex = null;
      _editGeneration++;
    });
    unawaited(_commitPoints(track, laneKind, paramLane, next, _editGeneration));
  }

  Future<void> _commitPoints(
    RemoteTrack track,
    int laneKind,
    ParameterLane? paramLane,
    List<AutomationPoint> points,
    int generation,
  ) async {
    final sorted = List<AutomationPoint>.of(points)
      ..sort((a, b) => a.time.compareTo(b.time));
    if (laneKind == _laneParameter) {
      if (paramLane == null) return;
      await _controller.setParamAutomation(
        trackId: track.id,
        slotKind: paramLane.slotKind,
        slotIndex: paramLane.slotIndex,
        paramIndex: paramLane.paramIndex,
        name: paramLane.name,
        points: sorted,
      );
    } else {
      await _controller.setLaneAutomation(track.id, laneKind, sorted);
    }
    await _controller.refreshState();
    if (!mounted || generation != _editGeneration) return;
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: _controller.project,
      builder: (context, project, _) {
        if (project == null) {
          return EmptyState(
            icon: Icons.multiline_chart_rounded,
            title: l10n.t('connectionLost'),
            message: l10n.t('errorNotConnected'),
          );
        }
        return ValueListenableBuilder<int?>(
          valueListenable: _controller.selectedTrackId,
          builder: (context, selectedId, _) {
            final track = project.trackById(selectedId);
            if (track == null) {
              return Column(
                children: [
                  _AutomationToolbar(
                    pointsCount: 0,
                    laneLabel: l10n.t('automationTitle'),
                    writeMode: false,
                    canClear: false,
                    canDeleteLane: false,
                    pixelsPerSecond: _pixelsPerSecond,
                    onWrite: null,
                    onClear: null,
                    onDeleteLane: null,
                    onZoomOut: () => _zoomBy(0.75),
                    onZoomIn: () => _zoomBy(1.33),
                    onFit: () => _fit(project),
                  ),
                  TrackChips(controller: _controller),
                  const Divider(height: 1),
                  Expanded(
                    child: EmptyState(
                      icon: Icons.show_chart_rounded,
                      title: l10n.t('chooseTrackFirst'),
                      message: l10n.t('selectSomething'),
                    ),
                  ),
                ],
              );
            }
            final paramLane = _paramLaneFor(track);
            final effectiveKind =
                _laneKind == _laneParameter && paramLane == null
                    ? _laneVolume
                    : _laneKind;
            final lanePoints = _lanePoints(track, effectiveKind, paramLane);
            final points = _dirty ? _points : lanePoints;
            final color = AppColors.track(track.colorIndex);
            final seconds = _contentSeconds(project);
            return Column(
              children: [
                _AutomationToolbar(
                  pointsCount: points.length,
                  laneLabel: _laneLabel(l10n, effectiveKind, paramLane),
                  writeMode: _writeMode,
                  canClear: points.isNotEmpty,
                  canDeleteLane:
                      effectiveKind == _laneParameter && paramLane != null,
                  pixelsPerSecond: _pixelsPerSecond,
                  onWrite: _toggleWrite,
                  onClear:
                      () => _clearLane(track, effectiveKind, paramLane, points),
                  onDeleteLane: () => _deleteLane(track, paramLane),
                  onZoomOut: () => _zoomBy(0.75),
                  onZoomIn: () => _zoomBy(1.33),
                  onFit: () => _fit(project),
                ),
                TrackChips(controller: _controller),
                _LaneBar(
                  track: track,
                  selectedKind: effectiveKind,
                  selectedParamLaneIndex: _paramLaneIndex,
                  onSelect: _selectLane,
                  onAddParameter: () => _addParamLane(track),
                ),
                if (_writeMode)
                  _WriteBanner(onWrite: () => _writeAtPlayhead(track)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _lastViewportWidth = constraints.maxWidth;
                      final contentWidth = math.max(
                        constraints.maxWidth,
                        seconds * _pixelsPerSecond + 20,
                      );
                      return _AutomationEditor(
                        controller: _controller,
                        project: project,
                        points: points,
                        laneKind: effectiveKind,
                        color: color,
                        pixelsPerSecond: _pixelsPerSecond,
                        contentWidth: contentWidth,
                        duration: seconds,
                        staticValue: _staticValue(track, effectiveKind),
                        scrollController: _horizontal,
                        dragIndex: _dragIndex,
                        onSeek: (time) => _controller.seek(time),
                        onAddPoint:
                            (time, value) => _addPoint(
                              track,
                              effectiveKind,
                              paramLane,
                              points,
                              time,
                              value,
                            ),
                        onDragStart: (index) => _beginDrag(index, points),
                        onDragUpdate:
                            (index, delta, height) =>
                                _updateDrag(index, delta, height, seconds),
                        onDragEnd:
                            () => _endDrag(track, effectiveKind, paramLane),
                        onDeletePoint:
                            (index) => _deletePoint(
                              track,
                              effectiveKind,
                              paramLane,
                              points,
                              index,
                            ),
                        valueLabel:
                            (value) => _laneValueLabel(effectiveKind, value),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _AutomationToolbar extends StatelessWidget {
  const _AutomationToolbar({
    required this.pointsCount,
    required this.laneLabel,
    required this.writeMode,
    required this.canClear,
    required this.canDeleteLane,
    required this.pixelsPerSecond,
    required this.onWrite,
    required this.onClear,
    required this.onDeleteLane,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final int pointsCount;
  final String laneLabel;
  final bool writeMode;
  final bool canClear;
  final bool canDeleteLane;
  final double pixelsPerSecond;
  final VoidCallback? onWrite;
  final VoidCallback? onClear;
  final VoidCallback? onDeleteLane;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(
            Icons.multiline_chart_rounded,
            size: 17,
            color: AppColors.accent,
          ),
          const SizedBox(width: 7),
          Text(
            l10n.t('automationTitle'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(width: 7),
          CountBadge(l10n.t('pointsCount', {'count': pointsCount})),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      laneLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ToggleTag(
                    label: 'W',
                    active: writeMode,
                    width: 26,
                    height: 26,
                    activeColor: AppColors.brand,
                    tooltip: l10n.t('writeMode'),
                    onTap: onWrite ?? () {},
                  ),
                  const SizedBox(width: 4),
                  AppIconButton(
                    icon: Icons.delete_sweep_rounded,
                    tooltip: l10n.t('clearLane'),
                    onPressed: canClear ? onClear : null,
                    minSize: 34,
                    size: 17,
                  ),
                  if (canDeleteLane)
                    AppIconButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: l10n.t('deleteLane'),
                      onPressed: onDeleteLane,
                      minSize: 34,
                      size: 17,
                      color: AppColors.danger,
                    ),
                  AppIconButton(
                    icon: Icons.remove_rounded,
                    tooltip: l10n.t('zoomOut'),
                    onPressed: onZoomOut,
                    minSize: 32,
                    size: 17,
                  ),
                  Text(
                    '${pixelsPerSecond.round()}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textFaint,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.add_rounded,
                    tooltip: l10n.t('zoomIn'),
                    onPressed: onZoomIn,
                    minSize: 32,
                    size: 17,
                  ),
                  AppIconButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: l10n.t('fitTimeline'),
                    onPressed: onFit,
                    minSize: 32,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _LaneBar extends StatelessWidget {
  const _LaneBar({
    required this.track,
    required this.selectedKind,
    required this.selectedParamLaneIndex,
    required this.onSelect,
    required this.onAddParameter,
  });

  final RemoteTrack track;
  final int selectedKind;
  final int? selectedParamLaneIndex;
  final void Function(int kind, [int? paramIndex]) onSelect;
  final VoidCallback onAddParameter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        color: AppColors.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          _LaneChip(
            label: l10n.t('volumeLane'),
            count: track.automation.volume.length,
            selected: selectedKind == _laneVolume,
            color: color,
            icon: Icons.volume_up_rounded,
            onTap: () => onSelect(_laneVolume),
          ),
          const SizedBox(width: 5),
          _LaneChip(
            label: l10n.t('panLane'),
            count: track.automation.pan.length,
            selected: selectedKind == _lanePan,
            color: color,
            icon: Icons.swap_horiz_rounded,
            onTap: () => onSelect(_lanePan),
          ),
          const SizedBox(width: 5),
          _LaneChip(
            label: l10n.t('sustainLane'),
            count: track.automation.sustain.length,
            selected: selectedKind == _laneSustain,
            color: color,
            icon: Icons.piano_rounded,
            onTap: () => onSelect(_laneSustain),
          ),
          for (final lane in track.automation.params) ...[
            const SizedBox(width: 5),
            _LaneChip(
              label: lane.name,
              count: lane.points.length,
              selected:
                  selectedKind == _laneParameter &&
                  selectedParamLaneIndex == lane.index,
              color: color,
              icon: Icons.tune_rounded,
              onTap: () => onSelect(_laneParameter, lane.index),
            ),
          ],
          const SizedBox(width: 5),
          _AddLaneChip(onTap: onAddParameter),
        ],
      ),
    );
  }
}

class _LaneChip extends StatelessWidget {
  const _LaneChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : AppColors.panel,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.62) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? color : AppColors.textFaint),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.text : AppColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: selected ? color : AppColors.textFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLaneChip extends StatelessWidget {
  const _AddLaneChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.t('addParameterLane'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 13, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                l10n.t('parameterLanes'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WriteBanner extends StatelessWidget {
  const _WriteBanner({required this.onWrite});

  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 8, 5),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.09),
        border: Border(
          bottom: BorderSide(color: AppColors.brand.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.t('writeHint'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.3,
                color: AppColors.brandLight,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onWrite,
            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
            label: Text(l10n.t('writeAtPlayhead')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandLight,
              minimumSize: const Size(30, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationEditor extends StatelessWidget {
  const _AutomationEditor({
    required this.controller,
    required this.project,
    required this.points,
    required this.laneKind,
    required this.color,
    required this.pixelsPerSecond,
    required this.contentWidth,
    required this.duration,
    required this.staticValue,
    required this.scrollController,
    required this.dragIndex,
    required this.onSeek,
    required this.onAddPoint,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDeletePoint,
    required this.valueLabel,
  });

  static const double rulerHeight = 26;
  static const double bottomPadding = 10;

  final RemoteController controller;
  final RemoteProject project;
  final List<AutomationPoint> points;
  final int laneKind;
  final Color color;
  final double pixelsPerSecond;
  final double contentWidth;
  final double duration;
  final double staticValue;
  final ScrollController scrollController;
  final int? dragIndex;
  final ValueChanged<double> onSeek;
  final void Function(double time, double value) onAddPoint;
  final ValueChanged<int> onDragStart;
  final void Function(int index, Offset delta, double editorHeight)
  onDragUpdate;
  final VoidCallback onDragEnd;
  final ValueChanged<int> onDeletePoint;
  final String Function(double value) valueLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final editorHeight = math.max(
          60.0,
          constraints.maxHeight - rulerHeight - bottomPadding,
        );
        double yFor(double value) =>
            rulerHeight + (1 - value.clamp(0.0, 1.0)) * editorHeight;
        return Scrollbar(
          controller: scrollController,
          notificationPredicate:
              (notification) => notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        final local = details.localPosition;
                        final time =
                            (local.dx / pixelsPerSecond)
                                .clamp(0.0, duration)
                                .toDouble();
                        if (local.dy <= rulerHeight) {
                          onSeek(time);
                          return;
                        }
                        final value =
                            (1 - (local.dy - rulerHeight) / editorHeight)
                                .clamp(0.0, 1.0)
                                .toDouble();
                        onAddPoint(time, value);
                      },
                      child: CustomPaint(
                        painter: _AutomationPainter(
                          project: project,
                          points: points,
                          color: color,
                          pixelsPerSecond: pixelsPerSecond,
                          editorTop: rulerHeight,
                          editorHeight: editorHeight,
                          laneKind: laneKind,
                          staticValue: staticValue,
                        ),
                      ),
                    ),
                  ),
                  if (points.isEmpty)
                    Positioned(
                      left: 20,
                      right: 20,
                      top: rulerHeight,
                      bottom: bottomPadding,
                      child: IgnorePointer(
                        child: Center(
                          child: Text(
                            l10n.t('addPointHint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textFaint.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: PlayheadBuilder(
                        controller: controller,
                        builder:
                            (context, position) => CustomPaint(
                              painter: _AutomationPlayheadPainter(
                                x: position * pixelsPerSecond,
                                top: rulerHeight,
                                bottom: constraints.maxHeight - bottomPadding,
                              ),
                            ),
                      ),
                    ),
                  ),
                  for (var index = 0; index < points.length; index++)
                    Positioned(
                      left: points[index].time * pixelsPerSecond - 13,
                      top: yFor(points[index].value) - 13,
                      width: 26,
                      height: 26,
                      child: _PointHandle(
                        point: points[index],
                        color: color,
                        selected: dragIndex == index,
                        valueText: valueLabel(points[index].value),
                        onTap: () {},
                        onLongPress: () => onDeletePoint(index),
                        onPanStart: () => onDragStart(index),
                        onPanUpdate:
                            (delta) => onDragUpdate(index, delta, editorHeight),
                        onPanEnd: onDragEnd,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PointHandle extends StatelessWidget {
  const _PointHandle({
    required this.point,
    required this.color,
    required this.selected,
    required this.valueText,
    required this.onTap,
    required this.onLongPress,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final AutomationPoint point;
  final Color color;
  final bool selected;
  final String valueText;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${formatClock(point.time)} · $valueText',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) => onPanUpdate(details.delta),
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanEnd,
        child: Center(
          child: Container(
            width: selected ? 13 : 11,
            height: selected ? 13 : 11,
            decoration: BoxDecoration(
              color: selected ? Colors.white : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? color : Colors.white.withValues(alpha: 0.65),
                width: selected ? 3 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutomationPainter extends CustomPainter {
  _AutomationPainter({
    required this.project,
    required this.points,
    required this.color,
    required this.pixelsPerSecond,
    required this.editorTop,
    required this.editorHeight,
    required this.laneKind,
    required this.staticValue,
  });

  final RemoteProject project;
  final List<AutomationPoint> points;
  final Color color;
  final double pixelsPerSecond;
  final double editorTop;
  final double editorHeight;
  final int laneKind;
  final double staticValue;

  double _y(double value) =>
      editorTop + (1 - value.clamp(0.0, 1.0)) * editorHeight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.background);

    final bar = barSeconds(
      project.tempoBpm,
      project.timeSigNum,
      project.timeSigDen,
    );
    final beat = beatSeconds(project.tempoBpm, project.timeSigDen);
    final barPx = bar * pixelsPerSecond;
    final beatPx = beat * pixelsPerSecond;

    // Ruler band.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, editorTop),
      Paint()..color = AppColors.backgroundElevated,
    );
    canvas.drawLine(
      Offset(0, editorTop - 0.5),
      Offset(size.width, editorTop - 0.5),
      Paint()..color = AppColors.border,
    );

    var labelStep = 1;
    while (barPx * labelStep < 54) {
      labelStep *= 2;
    }
    final barPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.075)
          ..strokeWidth = 1;
    final barStrongPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.13)
          ..strokeWidth = 1;
    final beatPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.035)
          ..strokeWidth = 1;
    final barCount = (size.width / barPx).ceil();
    for (var index = 0; index <= barCount; index++) {
      final x = index * barPx;
      final isLabel = index % labelStep == 0;
      canvas.drawLine(
        Offset(x, editorTop),
        Offset(x, size.height),
        isLabel ? barStrongPaint : barPaint,
      );
      if (isLabel) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${index + 1}',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x + 4, 6));
      }
      if (beatPx >= 8) {
        for (var beatIndex = 1; beatIndex < project.timeSigNum; beatIndex++) {
          final bx = x + beatIndex * beatPx;
          if (bx > size.width) break;
          canvas.drawLine(
            Offset(bx, editorTop),
            Offset(bx, size.height),
            beatPaint,
          );
        }
      }
    }

    // Horizontal value grid.
    final gridPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.055)
          ..strokeWidth = 1;
    for (final fraction in const <double>[0, 0.25, 0.5, 0.75, 1]) {
      final y = _y(fraction);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      if (fraction >= 1) continue;
      final label = TextPainter(
        text: TextSpan(
          text: '${(fraction * 100).round()}',
          style: TextStyle(
            color: AppColors.textFaint.withValues(alpha: 0.5),
            fontSize: 7.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(4, y - label.height - 1));
    }
    if (laneKind == _lanePan) {
      canvas.drawLine(
        Offset(0, _y(0.5)),
        Offset(size.width, _y(0.5)),
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = 1.2,
      );
    }

    if (points.isEmpty) {
      _drawDashedLine(
        canvas,
        Offset(0, _y(staticValue)),
        Offset(size.width, _y(staticValue)),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = 1.2,
      );
      return;
    }

    final sorted = List<AutomationPoint>.of(points)
      ..sort((a, b) => a.time.compareTo(b.time));
    final path = Path();
    if (laneKind == _laneSustain) {
      var current = 0.0;
      path.moveTo(0, _y(0));
      for (final point in sorted) {
        final x = point.time * pixelsPerSecond;
        path.lineTo(x, _y(current));
        current = point.value;
        path.lineTo(x, _y(current));
      }
      path.lineTo(size.width, _y(current));
    } else {
      path.moveTo(0, _y(sorted.first.value));
      for (final point in sorted) {
        path.lineTo(point.time * pixelsPerSecond, _y(point.value));
      }
      path.lineTo(size.width, _y(sorted.last.value));
    }

    final fill =
        Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.17),
            color.withValues(alpha: 0.015),
          ],
        ).createShader(Rect.fromLTWH(0, editorTop, size.width, editorHeight)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final distance = (end - start).distance;
    if (distance <= 0) return;
    final direction = (end - start) / distance;
    var travelled = 0.0;
    while (travelled < distance) {
      final a = start + direction * travelled;
      final b = start + direction * math.min(travelled + dash, distance);
      canvas.drawLine(a, b, paint);
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _AutomationPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.editorHeight != editorHeight ||
        oldDelegate.laneKind != laneKind ||
        oldDelegate.staticValue != staticValue ||
        oldDelegate.project.revision != project.revision ||
        oldDelegate.project.tempoBpm != project.tempoBpm;
  }
}

class _AutomationPlayheadPainter extends CustomPainter {
  _AutomationPlayheadPainter({
    required this.x,
    required this.top,
    required this.bottom,
  });

  final double x;
  final double top;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -2 || x > size.width + 2) return;
    canvas.drawRect(
      Rect.fromLTWH(x - 0.75, top, 1.5, math.max(0, bottom - top)),
      Paint()..color = AppColors.brand,
    );
    final triangle =
        Path()
          ..moveTo(x - 5, top)
          ..lineTo(x + 5, top)
          ..lineTo(x, top + 6)
          ..close();
    canvas.drawPath(triangle, Paint()..color = AppColors.brand);
  }

  @override
  bool shouldRepaint(covariant _AutomationPlayheadPainter oldDelegate) {
    return oldDelegate.x != x ||
        oldDelegate.top != top ||
        oldDelegate.bottom != bottom;
  }
}
