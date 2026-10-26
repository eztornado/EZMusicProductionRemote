import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/timeline_math.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playhead_builder.dart';
import 'sheets/add_track_sheet.dart';
import 'sheets/clip_sheet.dart';
import 'sheets/track_sheet.dart';

enum _TimelineTool { move, pan }

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.controller,
    required this.onOpenFx,
    required this.onOpenAutomation,
    this.active = true,
  });

  final RemoteController controller;
  final void Function([int? trackId]) onOpenFx;
  final void Function([int? trackId]) onOpenAutomation;
  final bool active;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  static const double _rowHeight = 64;
  static const double _automationHeight = 34;
  static const double _rulerHeight = 30;

  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  final ValueNotifier<double> _scrollX = ValueNotifier<double>(0);

  _TimelineTool _tool = _TimelineTool.move;
  bool _snap = true;
  bool _follow = true;
  bool _automationOverlay = false;
  double _pixelsPerSecond = 42;
  double _lastViewportWidth = 500;

  _ClipDrag? _drag;
  Timer? _followTimer;
  Timer? _seekTimer;
  double? _pendingSeek;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.selectedTrackId.addListener(_onSelectionChanged);
    _controller.selectedClipId.addListener(_onSelectionChanged);
    _followTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _followPlayhead(),
    );
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.selectedTrackId.removeListener(_onSelectionChanged);
    _controller.selectedClipId.removeListener(_onSelectionChanged);
    _followTimer?.cancel();
    _seekTimer?.cancel();
    _horizontal.dispose();
    _vertical.dispose();
    _scrollX.dispose();
    super.dispose();
  }

  double _barLength(RemoteProject project) =>
      barSeconds(project.tempoBpm, project.timeSigNum, project.timeSigDen);

  double _gridLength(RemoteProject project) => timelineGridSeconds(
    bpm: project.tempoBpm,
    numerator: project.timeSigNum,
    denominator: project.timeSigDen,
    pixelsPerSecond: _pixelsPerSecond,
  );

  double _contentSeconds(RemoteProject project) {
    final end = math.max(project.duration, project.lastClipEnd);
    final bar = _barLength(project);
    final minimum = bar * 8;
    final raw = math.max(end + 6, minimum);
    return (raw / bar).ceil() * bar;
  }

  void _followPlayhead() {
    if (!mounted || !widget.active || !_follow) return;
    if (!_horizontal.hasClients || !_controller.transport.value.isRunning) {
      return;
    }
    final position = _controller.estimatedPosition;
    final x = position * _pixelsPerSecond;
    final offset = _horizontal.offset;
    final viewport = _horizontal.position.viewportDimension;
    if (x > offset + viewport - 90 || x < offset + 24) {
      final target =
          (x - viewport * 0.28)
              .clamp(0.0, math.max(0.0, _horizontal.position.maxScrollExtent))
              .toDouble();
      _horizontal.jumpTo(target);
    }
  }

  void _zoomBy(double factor) {
    final viewport = _lastViewportWidth;
    final centerTime =
        _horizontal.hasClients
            ? (_horizontal.offset + viewport / 2) / _pixelsPerSecond
            : 0.0;
    final next = (_pixelsPerSecond * factor).clamp(6.0, 240.0);
    if (next == _pixelsPerSecond) return;
    setState(() => _pixelsPerSecond = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final target = centerTime * next - viewport / 2;
      _horizontal.jumpTo(
        target.clamp(0.0, math.max(0.0, _horizontal.position.maxScrollExtent)),
      );
    });
  }

  void _fit() {
    final project = _controller.currentProject;
    if (project == null) return;
    final viewport = math.max(120.0, _lastViewportWidth - 28);
    final seconds = _contentSeconds(project);
    final next = (viewport / seconds).clamp(6.0, 220.0);
    setState(() => _pixelsPerSecond = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontal.hasClients) _horizontal.jumpTo(0);
    });
  }

  void _seekNow(double seconds) {
    _pendingSeek = null;
    _seekTimer?.cancel();
    _seekTimer = null;
    _controller.seek(math.max(0, seconds));
  }

  void _queueSeek(double seconds) {
    _pendingSeek = seconds;
    _seekTimer ??= Timer(const Duration(milliseconds: 65), () {
      final target = _pendingSeek;
      _seekTimer = null;
      _pendingSeek = null;
      if (target != null) _controller.seek(math.max(0, target));
    });
  }

  void _onRuler(double localX) {
    final seconds =
        (localX + (_horizontal.hasClients ? _horizontal.offset : 0)) /
        _pixelsPerSecond;
    _queueSeek(seconds);
  }

  void _onRulerEnd() {
    final target = _pendingSeek;
    if (target != null) _seekNow(target);
  }

  void _startClipDrag(
    RemoteClip clip,
    RemoteTrack track,
    double localX,
    double width,
  ) {
    final mode =
        localX < 14
            ? ClipDragMode.trimStart
            : localX > width - 14
            ? ClipDragMode.trimEnd
            : ClipDragMode.move;
    setState(() {
      _drag = _ClipDrag(
        clip: clip,
        trackId: track.id,
        trackIndex: _controller.currentProject!.tracks.indexWhere(
          (item) => item.id == track.id,
        ),
        mode: mode,
        original: ClipGeometry(
          start: clip.start,
          length: clip.length,
          offset: clip.offset,
        ),
        current: ClipGeometry(
          start: clip.start,
          length: clip.length,
          offset: clip.offset,
        ),
      );
    });
    _controller.selectClip(clip.id);
  }

  void _updateClipDrag(DragUpdateDetails details, RemoteProject project) {
    final drag = _drag;
    if (drag == null) return;
    final grid = _gridLength(project);
    drag.deltaSeconds += details.delta.dx / _pixelsPerSecond;
    drag.deltaY += details.delta.dy;
    drag.current = dragClip(
      original: drag.original,
      mode: drag.mode,
      deltaSeconds: drag.deltaSeconds,
      snap: _snap,
      gridSeconds: grid,
    );
    if (project.tracks.isEmpty) {
      setState(() => _drag = null);
      return;
    }
    final stride = _rowHeight + (_automationOverlay ? _automationHeight : 0);
    final targetIndex = ((drag.trackIndex * stride + drag.deltaY) / stride)
        .floor()
        .clamp(0, project.tracks.length - 1);
    drag.targetTrackId = project.tracks[targetIndex].id;
    setState(() {});
  }

  void _cancelClipDrag() {
    if (_drag == null) return;
    setState(() => _drag = null);
  }

  Future<void> _endClipDrag() async {
    final drag = _drag;
    if (drag == null) return;
    setState(() => _drag = null);
    final moved = (drag.current.start - drag.original.start).abs() > 0.0001;
    final resized = (drag.current.length - drag.original.length).abs() > 0.0001;
    if (drag.mode == ClipDragMode.move) {
      if (!moved && drag.targetTrackId == drag.trackId) return;
      await _controller.moveClip(
        drag.clip.id,
        drag.targetTrackId,
        drag.current.start,
      );
    } else if (resized || moved) {
      await _controller.setClipBounds(
        drag.clip.id,
        start: drag.current.start,
        offset: drag.current.offset,
        length: drag.current.length,
      );
    }
  }

  void _onCanvasTap(TapDownDetails details, RemoteProject project) {
    final local = details.localPosition;
    final stride = _rowHeight + (_automationOverlay ? _automationHeight : 0);
    final trackIndex = (local.dy / stride).floor();
    if (trackIndex >= 0 && trackIndex < project.tracks.length) {
      _controller.selectTrack(project.tracks[trackIndex].id);
    }
    // The canvas sits inside the horizontal scroll view, so local coordinates
    // are already relative to the full timeline content. Do not add the
    // scroll offset again here (unlike the fixed-width ruler).
    final seconds = local.dx / _pixelsPerSecond;
    _seekNow(seconds);
  }

  Future<void> _openTrack(RemoteTrack track) async {
    await showTrackSheet(
      context,
      controller: _controller,
      trackId: track.id,
      onOpenFx: widget.onOpenFx,
      onOpenAutomation: widget.onOpenAutomation,
    );
  }

  Future<void> _openClip(RemoteClip clip) async {
    await showClipSheet(context, controller: _controller, clipId: clip.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: _controller.project,
      builder: (context, project, _) {
        if (project == null) {
          return EmptyState(
            icon: Icons.cloud_off_rounded,
            title: l10n.t('connectionLost'),
            message: l10n.t('errorNotConnected'),
          );
        }
        return Column(
          children: [
            _TimelineToolbar(
              tool: _tool,
              snap: _snap,
              follow: _follow,
              automation: _automationOverlay,
              pixelsPerSecond: _pixelsPerSecond,
              onTool: (tool) => setState(() => _tool = tool),
              onSnap: () => setState(() => _snap = !_snap),
              onFollow: () => setState(() => _follow = !_follow),
              onAutomation:
                  () =>
                      setState(() => _automationOverlay = !_automationOverlay),
              onZoomOut: () => _zoomBy(0.75),
              onZoomIn: () => _zoomBy(1.33),
              onFit: _fit,
              onAddTrack: () => showAddTrackSheet(context, _controller),
            ),
            if (project.tracks.isEmpty)
              Expanded(
                child: EmptyState(
                  icon: Icons.library_music_outlined,
                  title: l10n.t('noTracksTitle'),
                  message: l10n.t('noTracksBody'),
                  action: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            () => showAddTrackSheet(
                              context,
                              _controller,
                              initialType: 'instrument',
                            ),
                        icon: const Icon(Icons.piano_rounded, size: 18),
                        label: Text(l10n.t('addInstrumentTrack')),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            () => showAddTrackSheet(
                              context,
                              _controller,
                              initialType: 'audio',
                            ),
                        icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                        label: Text(l10n.t('addAudioTrack')),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final headerWidth =
                        constraints.maxWidth < 600
                            ? 140.0
                            : constraints.maxWidth < 980
                            ? 172.0
                            : 196.0;
                    final viewportWidth = constraints.maxWidth - headerWidth;
                    _lastViewportWidth = viewportWidth;
                    final seconds = _contentSeconds(project);
                    final contentWidth = math.max(
                      viewportWidth,
                      seconds * _pixelsPerSecond + 30,
                    );
                    final stride =
                        _rowHeight +
                        (_automationOverlay ? _automationHeight : 0);
                    final contentHeight = math.max(
                      constraints.maxHeight - _rulerHeight,
                      project.tracks.length * stride + 12,
                    );
                    final ruler = _Ruler(
                      controller: _controller,
                      project: project,
                      pixelsPerSecond: _pixelsPerSecond,
                      scrollX: _scrollX,
                      onSeek: _onRuler,
                      onSeekEnd: _onRulerEnd,
                    );
                    return Column(
                      children: [
                        SizedBox(
                          height: _rulerHeight,
                          child: Row(
                            children: [
                              Container(
                                width: headerWidth,
                                height: _rulerHeight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: const BoxDecoration(
                                  color: AppColors.backgroundElevated,
                                  border: Border(
                                    bottom: BorderSide(color: AppColors.border),
                                    right: BorderSide(color: AppColors.border),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.straighten_rounded,
                                      size: 13,
                                      color: AppColors.textFaint,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        '${l10n.t('tracksCount', {'count': project.tracks.length})}'
                                        ' · ${_pixelsPerSecond.round()} px/s',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: AppColors.textFaint,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(child: ruler),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _vertical,
                            child: SingleChildScrollView(
                              controller: _vertical,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: headerWidth,
                                    child: Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < project.tracks.length;
                                          index++
                                        )
                                          _TrackHeader(
                                            controller: _controller,
                                            track: project.tracks[index],
                                            index: index,
                                            selected:
                                                _controller
                                                    .selectedTrackId
                                                    .value ==
                                                project.tracks[index].id,
                                            automation: _automationOverlay,
                                            rowHeight: _rowHeight,
                                            automationHeight: _automationHeight,
                                            onOpen:
                                                () => _openTrack(
                                                  project.tracks[index],
                                                ),
                                            onFx:
                                                () => widget.onOpenFx(
                                                  project.tracks[index].id,
                                                ),
                                            onAutomation:
                                                () => widget.onOpenAutomation(
                                                  project.tracks[index].id,
                                                ),
                                            onMute:
                                                () => _controller.setTrackMute(
                                                  project.tracks[index].id,
                                                  !project.tracks[index].mute,
                                                ),
                                            onSolo:
                                                () => _controller.setTrackSolo(
                                                  project.tracks[index].id,
                                                  !project.tracks[index].solo,
                                                ),
                                            onArm:
                                                () => _controller.setTrackArmed(
                                                  project.tracks[index].id,
                                                  !project.tracks[index].armed,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: NotificationListener<
                                      ScrollNotification
                                    >(
                                      onNotification: (notification) {
                                        if (notification.metrics.axis ==
                                            Axis.horizontal) {
                                          _scrollX.value =
                                              notification.metrics.pixels;
                                        }
                                        return false;
                                      },
                                      child: Scrollbar(
                                        controller: _horizontal,
                                        notificationPredicate:
                                            (notification) =>
                                                notification.metrics.axis ==
                                                Axis.horizontal,
                                        child: SingleChildScrollView(
                                          controller: _horizontal,
                                          scrollDirection: Axis.horizontal,
                                          child: SizedBox(
                                            width: contentWidth,
                                            height: contentHeight,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Positioned.fill(
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTapDown:
                                                        (details) =>
                                                            _onCanvasTap(
                                                              details,
                                                              project,
                                                            ),
                                                    child: CustomPaint(
                                                      painter: _GridPainter(
                                                        project: project,
                                                        pixelsPerSecond:
                                                            _pixelsPerSecond,
                                                        rowHeight: _rowHeight,
                                                        automationHeight:
                                                            _automationOverlay
                                                                ? _automationHeight
                                                                : 0,
                                                        selectedTrackId:
                                                            _controller
                                                                .selectedTrackId
                                                                .value,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                for (
                                                  var index = 0;
                                                  index < project.tracks.length;
                                                  index++
                                                )
                                                  ..._buildClips(
                                                    context,
                                                    project,
                                                    project.tracks[index],
                                                    index,
                                                  ),
                                                Positioned.fill(
                                                  child: IgnorePointer(
                                                    child: PlayheadBuilder(
                                                      controller: _controller,
                                                      builder:
                                                          (
                                                            context,
                                                            position,
                                                          ) => CustomPaint(
                                                            painter:
                                                                _PlayheadLinePainter(
                                                                  x:
                                                                      position *
                                                                      _pixelsPerSecond,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildClips(
    BuildContext context,
    RemoteProject project,
    RemoteTrack track,
    int index,
  ) {
    final stride = _rowHeight + (_automationOverlay ? _automationHeight : 0);
    final widgets = <Widget>[];
    for (final clip in track.clips) {
      final drag = _drag;
      final isDragging = drag?.clip.id == clip.id;
      final geometry =
          isDragging
              ? drag!.current
              : ClipGeometry(
                start: clip.start,
                length: clip.length,
                offset: clip.offset,
              );
      var trackIndex = index;
      if (isDragging) {
        final target = project.tracks.indexWhere(
          (item) => item.id == drag!.targetTrackId,
        );
        if (target >= 0) trackIndex = target;
      }
      final top = trackIndex * stride + 2;
      final left = geometry.start * _pixelsPerSecond + 1.5;
      final width = math.max(12.0, geometry.length * _pixelsPerSecond - 3);
      final selected = _controller.selectedClipId.value == clip.id;
      final tile = _ClipTile(
        key: ValueKey('clip-${clip.id}'),
        clip: clip,
        track: track,
        width: width,
        height: _rowHeight - 4,
        selected: selected,
        onTap: () => _controller.selectClip(clip.id),
        onLongPress: () => _openClip(clip),
        onDoubleTap: () => _openClip(clip),
        onPanStart:
            _tool == _TimelineTool.move
                ? (details) =>
                    _startClipDrag(clip, track, details.localPosition.dx, width)
                : null,
        onPanUpdate:
            _tool == _TimelineTool.move
                ? (details) => _updateClipDrag(details, project)
                : null,
        onPanEnd: _tool == _TimelineTool.move ? (_) => _endClipDrag() : null,
        onPanCancel: _tool == _TimelineTool.move ? _cancelClipDrag : null,
      );
      widgets.add(
        Positioned(
          left: left,
          top: top,
          width: width,
          height: _rowHeight - 4,
          child: tile,
        ),
      );
    }
    return widgets;
  }
}

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.tool,
    required this.snap,
    required this.follow,
    required this.automation,
    required this.pixelsPerSecond,
    required this.onTool,
    required this.onSnap,
    required this.onFollow,
    required this.onAutomation,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
    required this.onAddTrack,
  });

  final _TimelineTool tool;
  final bool snap;
  final bool follow;
  final bool automation;
  final double pixelsPerSecond;
  final ValueChanged<_TimelineTool> onTool;
  final VoidCallback onSnap;
  final VoidCallback onFollow;
  final VoidCallback onAutomation;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFit;
  final VoidCallback onAddTrack;

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
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  AppIconButton(
                    icon: Icons.near_me_outlined,
                    tooltip: l10n.t('moveTool'),
                    active: tool == _TimelineTool.move,
                    onPressed: () => onTool(_TimelineTool.move),
                    minSize: 36,
                    size: 18,
                  ),
                  AppIconButton(
                    icon: Icons.pan_tool_outlined,
                    tooltip: l10n.t('panTool'),
                    active: tool == _TimelineTool.pan,
                    onPressed: () => onTool(_TimelineTool.pan),
                    minSize: 36,
                    size: 18,
                  ),
                  _divider(),
                  AppIconButton(
                    icon: Icons.straighten_rounded,
                    tooltip: l10n.t('snapToGrid'),
                    active: snap,
                    onPressed: onSnap,
                    minSize: 36,
                    size: 18,
                  ),
                  AppIconButton(
                    icon: Icons.center_focus_strong_rounded,
                    tooltip: l10n.t('followPlayhead'),
                    active: follow,
                    onPressed: onFollow,
                    minSize: 36,
                    size: 18,
                  ),
                  AppIconButton(
                    icon: Icons.multiline_chart_rounded,
                    tooltip: l10n.t('automationOverlay'),
                    active: automation,
                    onPressed: onAutomation,
                    minSize: 36,
                    size: 19,
                  ),
                  _divider(),
                  AppIconButton(
                    icon: Icons.remove_rounded,
                    tooltip: l10n.t('zoomOut'),
                    onPressed: onZoomOut,
                    minSize: 34,
                    size: 18,
                  ),
                  Text(
                    '${pixelsPerSecond.round()}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textFaint,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.add_rounded,
                    tooltip: l10n.t('zoomIn'),
                    onPressed: onZoomIn,
                    minSize: 34,
                    size: 18,
                  ),
                  AppIconButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: l10n.t('fitTimeline'),
                    onPressed: onFit,
                    minSize: 34,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: l10n.t('addTrack'),
              child: InkWell(
                onTap: onAddTrack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 17,
                        color: AppColors.accent,
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.library_music_rounded,
                        size: 15,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    color: AppColors.border,
  );
}

class _Ruler extends StatelessWidget {
  const _Ruler({
    required this.controller,
    required this.project,
    required this.pixelsPerSecond,
    required this.scrollX,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final RemoteController controller;
  final RemoteProject project;
  final double pixelsPerSecond;
  final ValueNotifier<double> scrollX;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => onSeek(details.localPosition.dx),
      onTapUp: (_) => onSeekEnd(),
      onHorizontalDragUpdate: (details) => onSeek(details.localPosition.dx),
      onHorizontalDragEnd: (_) => onSeekEnd(),
      child: ValueListenableBuilder<double>(
        valueListenable: scrollX,
        builder: (context, offset, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RulerPainter(
                    project: project,
                    pixelsPerSecond: pixelsPerSecond,
                    offset: offset,
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: PlayheadBuilder(
                    controller: controller,
                    builder:
                        (context, position) => CustomPaint(
                          painter: _RulerPlayheadPainter(
                            x: position * pixelsPerSecond - offset,
                          ),
                        ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.project,
    required this.pixelsPerSecond,
    required this.offset,
  });

  final RemoteProject project;
  final double pixelsPerSecond;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.backgroundElevated,
    );
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = AppColors.border,
    );

    final bar = barSeconds(
      project.tempoBpm,
      project.timeSigNum,
      project.timeSigDen,
    );
    final beat = beatSeconds(project.tempoBpm, project.timeSigDen);
    final barPx = bar * pixelsPerSecond;
    final beatPx = beat * pixelsPerSecond;
    var labelStep = 1;
    while (barPx * labelStep < 54) {
      labelStep *= 2;
    }

    final startSeconds = offset / pixelsPerSecond;
    final firstBar = (startSeconds / bar).floor();
    final endSeconds = (offset + size.width) / pixelsPerSecond;
    final lastBar = (endSeconds / bar).ceil();

    final tickPaint =
        Paint()
          ..color = AppColors.textFaint.withValues(alpha: 0.5)
          ..strokeWidth = 1;
    final barPaint =
        Paint()
          ..color = AppColors.borderStrong
          ..strokeWidth = 1;

    for (var barIndex = firstBar; barIndex <= lastBar; barIndex++) {
      final x = barIndex * bar * pixelsPerSecond - offset;
      if (x < -2 || x > size.width + 2) continue;
      canvas.drawLine(
        Offset(x, size.height * 0.35),
        Offset(x, size.height),
        barPaint,
      );
      if (barIndex % labelStep == 0) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${barIndex + 1}',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x + 4, 3));
      }

      if (beatPx >= 9) {
        for (var beatIndex = 1; beatIndex < project.timeSigNum; beatIndex++) {
          final bx = x + beatIndex * beatPx;
          if (bx < 0 || bx > size.width) continue;
          canvas.drawLine(
            Offset(bx, size.height * 0.68),
            Offset(bx, size.height),
            tickPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.project.revision != project.revision ||
        oldDelegate.project.tempoBpm != project.tempoBpm ||
        oldDelegate.project.timeSigNum != project.timeSigNum ||
        oldDelegate.project.timeSigDen != project.timeSigDen;
  }
}

class _RulerPlayheadPainter extends CustomPainter {
  _RulerPlayheadPainter({required this.x});

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -6 || x > size.width + 6) return;
    final paint = Paint()..color = AppColors.brand;
    final path =
        Path()
          ..moveTo(x - 5, size.height - 9)
          ..lineTo(x + 5, size.height - 9)
          ..lineTo(x + 5, size.height - 7)
          ..lineTo(x, size.height - 1)
          ..lineTo(x - 5, size.height - 7)
          ..close();
    canvas.drawPath(path, paint);
    canvas.drawRect(
      Rect.fromLTWH(x - 0.8, 0, 1.6, size.height - 9),
      Paint()..color = AppColors.brand.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPlayheadPainter oldDelegate) =>
      oldDelegate.x != x;
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.project,
    required this.pixelsPerSecond,
    required this.rowHeight,
    required this.automationHeight,
    required this.selectedTrackId,
  });

  final RemoteProject project;
  final double pixelsPerSecond;
  final double rowHeight;
  final double automationHeight;
  final int? selectedTrackId;

  @override
  void paint(Canvas canvas, Size size) {
    final stride = rowHeight + automationHeight;
    for (var index = 0; index < project.tracks.length; index++) {
      final top = index * stride;
      final track = project.tracks[index];
      final selected = track.id == selectedTrackId;
      final base =
          index.isEven ? AppColors.background : const Color(0xFF0E1014);
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, rowHeight),
        Paint()
          ..color =
              selected
                  ? Color.alphaBlend(
                    AppColors.accent.withValues(alpha: 0.055),
                    base,
                  )
                  : base,
      );
      if (automationHeight > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, top + rowHeight, size.width, automationHeight),
          Paint()
            ..color =
                selected
                    ? Color.alphaBlend(
                      AppColors.accent.withValues(alpha: 0.08),
                      const Color(0xFF111318),
                    )
                    : const Color(0xFF111318),
        );
      }
      canvas.drawLine(
        Offset(0, top + stride - 0.5),
        Offset(size.width, top + stride - 0.5),
        Paint()..color = AppColors.border.withValues(alpha: 0.8),
      );
      if (automationHeight > 0) {
        _paintAutomation(canvas, size, track, top + rowHeight, selected);
      }
    }

    final bar = barSeconds(
      project.tempoBpm,
      project.timeSigNum,
      project.timeSigDen,
    );
    final beat = beatSeconds(project.tempoBpm, project.timeSigDen);
    final barPx = bar * pixelsPerSecond;
    final beatPx = beat * pixelsPerSecond;
    final total = size.width;
    if (beatPx >= 7) {
      final beatPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.035)
            ..strokeWidth = 1;
      final beatCount = (total / beatPx).ceil();
      for (var i = 0; i < beatCount; i++) {
        final x = i * beatPx;
        if ((i % project.timeSigNum) == 0) continue;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), beatPaint);
      }
    }
    final barPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.09)
          ..strokeWidth = 1;
    final barCount = (total / barPx).ceil();
    for (var i = 0; i <= barCount; i++) {
      final x = i * barPx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), barPaint);
    }
  }

  void _paintAutomation(
    Canvas canvas,
    Size size,
    RemoteTrack track,
    double top,
    bool selected,
  ) {
    final lane = Rect.fromLTWH(0, top, size.width, automationHeight);
    final color = AppColors.track(track.colorIndex);
    final points = track.automation.volume;
    final path = Path();
    final fill = Path();
    final height = automationHeight - 8;
    final baseline = top + 4;

    if (points.isEmpty) {
      final y = baseline + (1 - track.volume.clamp(0.0, 1.0)) * height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color.withValues(alpha: selected ? 0.65 : 0.4)
          ..strokeWidth = 1.3,
      );
      return;
    }
    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));
    path.moveTo(
      sorted.first.time * pixelsPerSecond,
      baseline + (1 - sorted.first.value) * height,
    );
    fill.moveTo(0, lane.bottom);
    fill.lineTo(
      sorted.first.time * pixelsPerSecond,
      baseline + (1 - sorted.first.value) * height,
    );
    for (final point in sorted) {
      final x = point.time * pixelsPerSecond;
      final y = baseline + (1 - point.value) * height;
      path.lineTo(x, y);
      fill.lineTo(x, y);
    }
    fill.lineTo(sorted.last.time * pixelsPerSecond, lane.bottom);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(lane),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: selected ? 0.95 : 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    for (final point in sorted) {
      canvas.drawCircle(
        Offset(
          point.time * pixelsPerSecond,
          baseline + (1 - point.value) * height,
        ),
        2.2,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.project != project ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond ||
        oldDelegate.automationHeight != automationHeight ||
        oldDelegate.selectedTrackId != selectedTrackId;
  }
}

class _PlayheadLinePainter extends CustomPainter {
  _PlayheadLinePainter({required this.x});

  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -2 || x > size.width + 2) return;
    canvas.drawRect(
      Rect.fromLTWH(x - 3, 0, 6, size.height),
      Paint()
        ..color = AppColors.brand.withValues(alpha: 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRect(
      Rect.fromLTWH(x - 0.75, 0, 1.5, size.height),
      Paint()..color = AppColors.brand,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayheadLinePainter oldDelegate) =>
      oldDelegate.x != x;
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({
    required this.controller,
    required this.track,
    required this.index,
    required this.selected,
    required this.automation,
    required this.rowHeight,
    required this.automationHeight,
    required this.onOpen,
    required this.onFx,
    required this.onAutomation,
    required this.onMute,
    required this.onSolo,
    required this.onArm,
  });

  final RemoteController controller;
  final RemoteTrack track;
  final int index;
  final bool selected;
  final bool automation;
  final double rowHeight;
  final double automationHeight;
  final VoidCallback onOpen;
  final VoidCallback onFx;
  final VoidCallback onAutomation;
  final VoidCallback onMute;
  final VoidCallback onSolo;
  final VoidCallback onArm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    final stride = rowHeight + (automation ? automationHeight : 0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => controller.selectTrack(track.id),
      onLongPress: onOpen,
      child: Container(
        height: stride,
        decoration: BoxDecoration(
          color:
              selected
                  ? Color.alphaBlend(
                    AppColors.accent.withValues(alpha: 0.07),
                    AppColors.backgroundElevated,
                  )
                  : AppColors.backgroundElevated,
          border: const Border(
            bottom: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 6, 5, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(2),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                (index + 1).toString().padLeft(2, '0'),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textFaint,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  track.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: onOpen,
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 15,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                track.isInstrument
                                    ? Icons.piano_rounded
                                    : Icons.graphic_eq_rounded,
                                size: 10,
                                color: AppColors.textFaint,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  track.isInstrument
                                      ? (track.hasInstrument
                                          ? track.instrument
                                          : l10n.t('unknown'))
                                      : '${l10n.t('inputChannel')} ${track.inputChannel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _MiniToggle(
                                label: 'M',
                                active: track.mute,
                                color: AppColors.warning,
                                onTap: onMute,
                                tooltip: l10n.t('mute'),
                              ),
                              const SizedBox(width: 3),
                              _MiniToggle(
                                label: 'S',
                                active: track.solo,
                                color: AppColors.success,
                                onTap: onSolo,
                                tooltip: l10n.t('solo'),
                              ),
                              const SizedBox(width: 3),
                              _MiniToggle(
                                label: 'R',
                                active: track.armed,
                                color: AppColors.record,
                                onTap: onArm,
                                tooltip: l10n.t('arm'),
                              ),
                              const Spacer(),
                              if (track.fx.isNotEmpty)
                                InkWell(
                                  onTap: onFx,
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.panelAlt,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: Text(
                                      '${track.fx.length} FX',
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 3),
                              InkWell(
                                onTap: onAutomation,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.multiline_chart_rounded,
                                    size: 13,
                                    color:
                                        track.automation.isEmpty
                                            ? AppColors.textFaint
                                            : AppColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (automation)
              InkWell(
                onTap: onAutomation,
                child: Container(
                  height: automationHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: const BoxDecoration(
                    color: Color(0xFF111318),
                    border: Border(top: BorderSide(color: Color(0x33000000))),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.show_chart_rounded,
                        size: 12,
                        color: color.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        l10n.t('volumeShort'),
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: AppColors.textFaint,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDb(track.volume),
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: AppColors.textFaint,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 20,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.2) : AppColors.panel,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.65) : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: active ? color : AppColors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    super.key,
    required this.clip,
    required this.track,
    required this.width,
    required this.height,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDoubleTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  final RemoteClip clip;
  final RemoteTrack track;
  final double width;
  final double height;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;
  final void Function(DragStartDetails details)? onPanStart;
  final void Function(DragUpdateDetails details)? onPanUpdate;
  final void Function(DragEndDetails details)? onPanEnd;
  final VoidCallback? onPanCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    final showText = width > 54;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      onPanCancel: onPanCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                color.withValues(alpha: clip.muted ? 0.09 : 0.26),
                AppColors.surface,
              ),
              Color.alphaBlend(
                color.withValues(alpha: clip.muted ? 0.05 : 0.13),
                AppColors.background,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                selected
                    ? AppColors.text
                    : color.withValues(alpha: clip.muted ? 0.3 : 0.62),
            width: selected ? 1.4 : 1,
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ]
                  : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _ClipArtPainter(
                  clip: clip,
                  color: color,
                  selected: selected,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? 1 : 0.82),
                  ),
                ),
              ),
              if (showText)
                Positioned(
                  left: 6,
                  right: 4,
                  top: 5,
                  child: Row(
                    children: [
                      Icon(
                        clip.isMidi
                            ? Icons.piano_rounded
                            : Icons.graphic_eq_rounded,
                        size: 10,
                        color: color.withValues(alpha: 0.95),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          clip.isMidi
                              ? l10n.t('midiClip')
                              : l10n.t('audioClip'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text.withValues(
                              alpha: clip.muted ? 0.5 : 0.92,
                            ),
                          ),
                        ),
                      ),
                      if (width > 100)
                        Text(
                          clip.isMidi
                              ? l10n.t('notesCount', {
                                'count': clip.notes.length,
                              })
                              : formatClock(clip.length, showMillis: false),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8,
                            color: AppColors.textFaint.withValues(
                              alpha: clip.muted ? 0.5 : 0.85,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (clip.muted)
                Center(
                  child: Icon(
                    Icons.volume_off_rounded,
                    size: math.min(18, width * 0.4),
                    color: AppColors.textFaint.withValues(alpha: 0.75),
                  ),
                ),
              if (selected && width > 32) ...[
                const Positioned(
                  left: 0,
                  top: 6,
                  bottom: 6,
                  width: 9,
                  child: _TrimHandle(),
                ),
                const Positioned(
                  right: 0,
                  top: 6,
                  bottom: 6,
                  width: 9,
                  child: _TrimHandle(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 3,
        height: 18,
        decoration: BoxDecoration(
          color: AppColors.text.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ClipArtPainter extends CustomPainter {
  _ClipArtPainter({
    required this.clip,
    required this.color,
    required this.selected,
  });

  final RemoteClip clip;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final fadePaint = Paint()..color = Colors.black.withValues(alpha: 0.2);
    if (clip.fadeIn > 0) {
      final width = (clip.fadeIn / math.max(0.0001, clip.length)) * size.width;
      final path =
          Path()
            ..moveTo(0, 0)
            ..lineTo(width.clamp(0, size.width), 0)
            ..lineTo(0, size.height)
            ..close();
      canvas.drawPath(path, fadePaint);
    }
    if (clip.fadeOut > 0) {
      final width = (clip.fadeOut / math.max(0.0001, clip.length)) * size.width;
      final path =
          Path()
            ..moveTo(size.width, 0)
            ..lineTo(size.width - width.clamp(0, size.width), 0)
            ..lineTo(size.width, size.height)
            ..close();
      canvas.drawPath(path, fadePaint);
    }

    if (clip.isMidi && clip.notes.isNotEmpty) {
      _paintNotes(canvas, size);
    } else if (!clip.isMidi) {
      _paintAudioSketch(canvas, size);
    }
  }

  void _paintNotes(Canvas canvas, Size size) {
    final pitches = clip.notes.map((note) => note.pitch).toList()..sort();
    final minPitch = pitches.first;
    final maxPitch = pitches.last;
    final range = math.max(1, maxPitch - minPitch);
    final top = 15.0;
    final height = math.max(6.0, size.height - top - 4);
    final notePaint =
        Paint()..color = color.withValues(alpha: selected ? 0.9 : 0.68);
    for (final note in clip.notes) {
      final x = (note.start / math.max(0.0001, clip.length)) * size.width;
      final w = (note.length / math.max(0.0001, clip.length)) * size.width;
      if (x > size.width || x + w < 0) continue;
      final y = top + (1 - (note.pitch - minPitch) / range) * (height - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x.clamp(0.0, size.width), y, math.max(1.2, w), 2.2),
          const Radius.circular(1),
        ),
        notePaint,
      );
    }
  }

  void _paintAudioSketch(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color.withValues(alpha: selected ? 0.4 : 0.26)
          ..strokeWidth = 1;
    final top = 16.0;
    final height = math.max(4.0, size.height - top - 5);
    final center = top + height / 2;
    final step = 3.0;
    for (var x = 3.0; x < size.width - 3; x += step) {
      final t = x / math.max(1, size.width);
      final amp = (math.sin(t * 34 + clip.id) * 0.35 +
              math.sin(t * 13 + 2) * 0.22 +
              0.43)
          .abs()
          .clamp(0.08, 1.0);
      canvas.drawLine(
        Offset(x, center - height * amp / 2),
        Offset(x, center + height * amp / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClipArtPainter oldDelegate) {
    return oldDelegate.clip != clip ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}

class _ClipDrag {
  _ClipDrag({
    required this.clip,
    required this.trackId,
    required this.trackIndex,
    required this.mode,
    required this.original,
    required this.current,
  }) : targetTrackId = trackId;

  final RemoteClip clip;
  final int trackId;
  final int trackIndex;
  final ClipDragMode mode;
  final ClipGeometry original;
  ClipGeometry current;
  int targetTrackId;
  double deltaSeconds = 0;
  double deltaY = 0;
}
