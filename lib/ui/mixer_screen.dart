import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fader.dart';
import '../widgets/peak_meter.dart';
import 'sheets/add_track_sheet.dart';
import 'sheets/master_fx_sheet.dart';
import 'sheets/track_sheet.dart';

/// Horizontal console with one strip per track and a master strip.
///
/// The mixer is intentionally separate from the timeline: on a phone the
/// timeline is already dense, so the mixer gets its own destination with
/// larger touch targets for faders, pan knobs and meters.
class MixerScreen extends StatefulWidget {
  const MixerScreen({
    super.key,
    required this.controller,
    required this.onOpenFx,
    required this.onOpenAutomation,
  });

  final RemoteController controller;
  final void Function([int? trackId]) onOpenFx;
  final void Function([int? trackId]) onOpenAutomation;

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  final ScrollController _horizontal = ScrollController();

  RemoteController get _controller => widget.controller;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _addTrack() async {
    final id = await showAddTrackSheet(context, _controller);
    if (id == null || !mounted) return;
    // The project snapshot arrives asynchronously. Give it a moment, then
    // reveal the new strip at the end of the console.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || !_horizontal.hasClients) return;
    await _horizontal.animateTo(
      _horizontal.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
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

  Future<void> _openMasterFx() async {
    await showMasterFxSheet(context, _controller);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: _controller.project,
      builder: (context, project, _) {
        if (project == null) {
          return EmptyState(
            icon: Icons.equalizer_rounded,
            title: l10n.t('connectionLost'),
            message: l10n.t('errorNotConnected'),
          );
        }
        return Column(
          children: [
            _MixerToolbar(
              channelCount: project.tracks.length,
              onAddTrack: _addTrack,
              onMaster: _openMasterFx,
            ),
            Expanded(
              child:
                  project.tracks.isEmpty
                      ? EmptyState(
                        icon: Icons.equalizer_rounded,
                        title: l10n.t('mixerEmpty'),
                        message: l10n.t('mixerHint'),
                        action: FilledButton.icon(
                          onPressed: _addTrack,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(l10n.t('addTrack')),
                        ),
                      )
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final stripWidth =
                              constraints.maxWidth < 620 ? 88.0 : 102.0;
                          // Landscape phones can leave very little height
                          // after the app bar, transport and navigation bar.
                          // Keep a usable strip height and let the console
                          // scroll vertically instead of overflowing.
                          final consoleHeight = math.max(
                            constraints.maxHeight,
                            320.0,
                          );
                          return SingleChildScrollView(
                            child: SizedBox(
                              height: consoleHeight,
                              child: ValueListenableBuilder<int?>(
                                valueListenable: _controller.selectedTrackId,
                                builder: (context, selectedId, _) {
                                  return Scrollbar(
                                    controller: _horizontal,
                                    notificationPredicate:
                                        (notification) =>
                                            notification.metrics.axis ==
                                            Axis.horizontal,
                                    child: ListView.builder(
                                      controller: _horizontal,
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        10,
                                        10,
                                        12,
                                      ),
                                      itemCount: project.tracks.length + 1,
                                      itemBuilder: (context, index) {
                                        if (index == project.tracks.length) {
                                          return _MasterStrip(
                                            controller: _controller,
                                            project: project,
                                            width: stripWidth,
                                            onOpenFx: _openMasterFx,
                                          );
                                        }
                                        final track = project.tracks[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: _ChannelStrip(
                                            controller: _controller,
                                            track: track,
                                            index: index,
                                            width: stripWidth,
                                            selected: track.id == selectedId,
                                            onOpen: () => _openTrack(track),
                                            onFx:
                                                () => widget.onOpenFx(track.id),
                                            onAutomation:
                                                () => widget.onOpenAutomation(
                                                  track.id,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        );
      },
    );
  }
}

class _MixerToolbar extends StatelessWidget {
  const _MixerToolbar({
    required this.channelCount,
    required this.onAddTrack,
    required this.onMaster,
  });

  final int channelCount;
  final VoidCallback onAddTrack;
  final VoidCallback onMaster;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          return Row(
            children: [
              const SizedBox(width: 12),
              const Icon(
                Icons.equalizer_rounded,
                size: 17,
                color: AppColors.accent,
              ),
              const SizedBox(width: 7),
              Text(
                l10n.t('mixerTitle'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 7),
              CountBadge(l10n.t('channelCount', {'count': channelCount})),
              if (wide) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.t('mixerHint'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              AppIconButton(
                icon: Icons.surround_sound_rounded,
                tooltip: l10n.t('masterFx'),
                onPressed: onMaster,
                minSize: 36,
                size: 18,
                color: AppColors.warning,
              ),
              Tooltip(
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
                        SizedBox(width: 4),
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
              const SizedBox(width: 10),
            ],
          );
        },
      ),
    );
  }
}

class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({
    required this.controller,
    required this.track,
    required this.index,
    required this.width,
    required this.selected,
    required this.onOpen,
    required this.onFx,
    required this.onAutomation,
  });

  final RemoteController controller;
  final RemoteTrack track;
  final int index;
  final double width;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onFx;
  final VoidCallback onAutomation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 390;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => controller.selectTrack(track.id),
          onLongPress: onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: width,
            decoration: BoxDecoration(
              color:
                  selected
                      ? Color.alphaBlend(
                        AppColors.accent.withValues(alpha: 0.06),
                        AppColors.surface,
                      )
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selected ? color.withValues(alpha: 0.68) : AppColors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(height: 3, color: color),
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 7, 4, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TrackColorDot(
                            colorIndex: track.colorIndex,
                            size: 7,
                            glow: selected,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textFaint,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: onOpen,
                            borderRadius: BorderRadius.circular(5),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 14,
                                color: AppColors.textFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      if (!tight) ...[
                        const SizedBox(height: 1),
                        Text(
                          track.isInstrument
                              ? (track.hasInstrument
                                  ? track.instrument
                                  : l10n.t('instrumentLabel'))
                              : '${l10n.t('inputChannel')} ${track.inputChannel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.only(top: tight ? 5 : 8, bottom: 2),
                  child: Column(
                    children: [
                      PanKnob(
                        value: track.pan,
                        size: tight ? 32 : 40,
                        label: l10n.t('panShort'),
                        onChanged:
                            (value) =>
                                controller.previewTrackPan(track.id, value),
                        onChangeEnd:
                            (value) =>
                                controller.commitTrackMix(track.id, pan: value),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatPan(track.pan),
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppColors.textFaint,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: GainFader(
                              value: track.volume,
                              maxGain: 2,
                              width: math.min(44, width - 36),
                              label: '${track.name} ${l10n.t('volumeShort')}',
                              onChanged:
                                  (value) => controller.previewTrackVolume(
                                    track.id,
                                    value,
                                  ),
                              onChangeEnd:
                                  (value) => controller.commitTrackMix(
                                    track.id,
                                    volume: value,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 9,
                          child: PeakMeter(
                            controller: controller,
                            trackId: track.id,
                            width: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  formatDb(track.volume),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: ToggleTag(
                          label: 'M',
                          active: track.mute,
                          height: 22,
                          activeColor: AppColors.warning,
                          tooltip: l10n.t('mute'),
                          onTap:
                              () => controller.setTrackMute(
                                track.id,
                                !track.mute,
                              ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: ToggleTag(
                          label: 'S',
                          active: track.solo,
                          height: 22,
                          activeColor: AppColors.success,
                          tooltip: l10n.t('solo'),
                          onTap:
                              () => controller.setTrackSolo(
                                track.id,
                                !track.solo,
                              ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: ToggleTag(
                          label: 'R',
                          active: track.armed,
                          height: 22,
                          activeColor: AppColors.record,
                          tooltip: l10n.t('arm'),
                          onTap:
                              () => controller.setTrackArmed(
                                track.id,
                                !track.armed,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StripAction(
                          icon: Icons.tune_rounded,
                          label:
                              track.fx.isEmpty ? 'FX' : 'FX ${track.fx.length}',
                          active: track.fx.isNotEmpty,
                          tooltip: l10n.t('effectsTitle'),
                          onTap: onFx,
                        ),
                      ),
                      const SizedBox(width: 3),
                      _StripAction(
                        icon: Icons.multiline_chart_rounded,
                        label: '',
                        active: !track.automation.isEmpty,
                        tooltip: l10n.t('automationTitle'),
                        onTap: onAutomation,
                        square: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MasterStrip extends StatelessWidget {
  const _MasterStrip({
    required this.controller,
    required this.project,
    required this.width,
    required this.onOpenFx,
  });

  final RemoteController controller;
  final RemoteProject project;
  final double width;
  final VoidCallback onOpenFx;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 390;
        return GestureDetector(
          onTap: onOpenFx,
          child: Container(
            width: width,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                AppColors.warning.withValues(alpha: 0.035),
                AppColors.surface,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.42),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(height: 3, color: AppColors.warning),
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 8, 7, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.surround_sound_rounded,
                            size: 11,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'MASTER',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: AppColors.warning.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.t('master'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      if (!tight) ...[
                        const SizedBox(height: 1),
                        Text(
                          '${l10n.t('stereo')} · ${l10n.t('output')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.only(top: tight ? 5 : 8, bottom: 2),
                  child: Column(
                    children: [
                      Container(
                        width: tight ? 32 : 40,
                        height: tight ? 32 : 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.panel,
                          border: Border.all(color: AppColors.borderStrong),
                        ),
                        child: Icon(
                          Icons.surround_sound_rounded,
                          size: tight ? 15 : 18,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'L  R',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textFaint,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: GainFader(
                              value: project.masterGain,
                              maxGain: 4,
                              width: math.min(40, width - 38),
                              label: l10n.t('masterGain'),
                              onChanged: controller.previewMasterGain,
                              onChangeEnd: controller.commitMasterGain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 21,
                          child: PeakMeter(controller: controller, width: 9),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  formatDb(project.masterGain),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.panelAlt,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    l10n.t('stereo').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
                  child: _StripAction(
                    icon: Icons.tune_rounded,
                    label:
                        project.masterFx.isEmpty
                            ? 'FX'
                            : 'FX ${project.masterFx.length}',
                    active: project.masterFx.isNotEmpty,
                    tooltip: l10n.t('masterFx'),
                    onTap: onOpenFx,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StripAction extends StatelessWidget {
  const _StripAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.square = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textFaint;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: square ? 26 : null,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accentSoft : AppColors.panelAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  active
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
