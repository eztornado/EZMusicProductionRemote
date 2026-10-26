import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../l10n/strings.dart';
import '../../models/project.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/color_palette.dart';
import '../../widgets/common.dart';

Future<void> showTrackSheet(
  BuildContext context, {
  required RemoteController controller,
  required int trackId,
  required void Function([int? trackId]) onOpenFx,
  required void Function([int? trackId]) onOpenAutomation,
}) {
  return showAppSheet<void>(
    context,
    maxWidth: 600,
    heightFactor: 0.93,
    builder:
        (ctx) => _TrackSheet(
          controller: controller,
          trackId: trackId,
          onOpenFx: onOpenFx,
          onOpenAutomation: onOpenAutomation,
        ),
  );
}

class _TrackSheet extends StatelessWidget {
  const _TrackSheet({
    required this.controller,
    required this.trackId,
    required this.onOpenFx,
    required this.onOpenAutomation,
  });

  final RemoteController controller;
  final int trackId;
  final void Function([int? trackId]) onOpenFx;
  final void Function([int? trackId]) onOpenAutomation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: controller.project,
      builder: (context, project, _) {
        final track = project?.trackById(trackId);
        if (track == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: l10n.t('errorNotFound'),
              message: l10n.t('selectTrack'),
              compact: true,
            ),
          );
        }
        return _TrackEditor(
          key: ValueKey('track-editor-${track.id}'),
          controller: controller,
          track: track,
          onOpenFx: onOpenFx,
          onOpenAutomation: onOpenAutomation,
        );
      },
    );
  }
}

class _TrackEditor extends StatefulWidget {
  const _TrackEditor({
    super.key,
    required this.controller,
    required this.track,
    required this.onOpenFx,
    required this.onOpenAutomation,
  });

  final RemoteController controller;
  final RemoteTrack track;
  final void Function([int? trackId]) onOpenFx;
  final void Function([int? trackId]) onOpenAutomation;

  @override
  State<_TrackEditor> createState() => _TrackEditorState();
}

class _TrackEditorState extends State<_TrackEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.track.name,
  );
  late final FocusNode _nameFocus = FocusNode();

  RemoteController get _controller => widget.controller;
  RemoteTrack get _track => widget.track;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _saveName();
    });
  }

  @override
  void didUpdateWidget(covariant _TrackEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_nameFocus.hasFocus && _name.text != widget.track.name) {
      _name.value = TextEditingValue(
        text: widget.track.name,
        selection: TextSelection.collapsed(offset: widget.track.name.length),
      );
    }
  }

  @override
  void dispose() {
    _saveName();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _saveName() {
    final value = _name.text.trim();
    if (value.isNotEmpty && value != _track.name) {
      _controller.renameTrack(_track.id, value);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('deleteTrack'),
      message:
          '${l10n.t('deleteTrackConfirm', {'name': _track.name})}\n\n'
          '${l10n.t('deleteTrackConfirmDesc')}',
      confirmLabel: l10n.t('delete'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    final removed = await _controller.removeTrack(_track.id);
    if (removed && mounted) Navigator.of(context).pop();
  }

  void _openFx() {
    Navigator.of(context).pop();
    widget.onOpenFx(_track.id);
  }

  void _openAutomation() {
    Navigator.of(context).pop();
    widget.onOpenAutomation(_track.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(_track.colorIndex);
    final clipCount = _track.clips.length;
    final automationPoints =
        _track.automation.volume.length +
        _track.automation.pan.length +
        _track.automation.sustain.length +
        _track.automation.params.fold<int>(
          0,
          (sum, lane) => sum + lane.points.length,
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        SheetHeader(
          title: _track.name,
          subtitle:
              '${_track.isInstrument ? l10n.t('addInstrumentTrack') : l10n.t('addAudioTrack')}'
              ' · ${l10n.t('clipsCount', {'count': clipCount})}',
          icon:
              _track.isInstrument
                  ? Icons.piano_rounded
                  : Icons.graphic_eq_rounded,
        ),
        _Card(
          children: [
            Row(
              children: [
                TrackColorDot(
                  colorIndex: _track.colorIndex,
                  size: 10,
                  glow: true,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _name,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.done,
                    maxLength: 40,
                    onSubmitted: (_) {
                      _saveName();
                      _nameFocus.unfocus();
                    },
                    decoration: InputDecoration(
                      labelText: l10n.t('trackName'),
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: l10n.t('done'),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        onPressed: () {
                          _saveName();
                          _nameFocus.unfocus();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SectionLabel(l10n.t('trackColor')),
            ColorPalettePicker(
              selectedIndex: _track.colorIndex,
              onSelected:
                  (index) => _controller.setTrackColor(_track.id, index),
              size: 26,
              spacing: 8,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                ToggleTag(
                  label: l10n.t('mute'),
                  active: _track.mute,
                  activeColor: AppColors.warning,
                  height: 28,
                  onTap:
                      () => _controller.setTrackMute(_track.id, !_track.mute),
                ),
                const SizedBox(width: 6),
                ToggleTag(
                  label: l10n.t('solo'),
                  active: _track.solo,
                  activeColor: AppColors.success,
                  height: 28,
                  onTap:
                      () => _controller.setTrackSolo(_track.id, !_track.solo),
                ),
                const SizedBox(width: 6),
                ToggleTag(
                  label: l10n.t('arm'),
                  active: _track.armed,
                  activeColor: AppColors.record,
                  height: 28,
                  onTap:
                      () => _controller.setTrackArmed(_track.id, !_track.armed),
                ),
                const Spacer(),
                if (automationPoints > 0)
                  CountBadge(
                    l10n.t('pointsCount', {'count': automationPoints}),
                    color: color,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            SectionLabel(l10n.t('mixerTitle')),
            _SliderRow(
              label: l10n.t('volumeShort'),
              value: _track.volume.clamp(0.0, 2.0).toDouble(),
              min: 0,
              max: 2,
              valueLabel: formatDb(_track.volume),
              onChanged:
                  (value) => _controller.previewTrackVolume(_track.id, value),
              onChangeEnd:
                  (value) =>
                      _controller.commitTrackMix(_track.id, volume: value),
            ),
            _SliderRow(
              label: l10n.t('panShort'),
              value: _track.pan.clamp(-1.0, 1.0).toDouble(),
              min: -1,
              max: 1,
              valueLabel: formatPan(_track.pan),
              onChanged:
                  (value) => _controller.previewTrackPan(_track.id, value),
              onChangeEnd:
                  (value) => _controller.commitTrackMix(_track.id, pan: value),
            ),
            if (!_track.isInstrument) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('inputChannel'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                  _Stepper(
                    value: '${_track.inputChannel}',
                    onMinus:
                        () => _controller.setTrackInput(
                          _track.id,
                          (_track.inputChannel - 1).clamp(0, 128),
                        ),
                    onPlus:
                        () => _controller.setTrackInput(
                          _track.id,
                          (_track.inputChannel + 1).clamp(0, 128),
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            Row(
              children: [
                Expanded(
                  child: SectionLabel(
                    l10n.t(
                      _track.isInstrument
                          ? 'instrumentSection'
                          : 'insertEffects',
                    ),
                  ),
                ),
                CountBadge(l10n.t('fxSlots', {'count': _track.fx.length})),
              ],
            ),
            if (_track.isInstrument) ...[
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Icon(Icons.piano_rounded, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _track.hasInstrument
                              ? _track.instrument
                              : l10n.t('none'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        if (_track.hasMidiFx)
                          Text(
                            '${l10n.t('midiFxLabel')}: ${_track.midiFx}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textFaint,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_track.fx.isEmpty)
              Text(
                l10n.t('noEffects'),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textFaint,
                ),
              )
            else
              for (var index = 0; index < _track.fx.length; index++)
                _FxRow(
                  slot: _track.fx[index],
                  onBypass:
                      () => _controller.setFxBypass(
                        _track.id,
                        _track.fx[index].index,
                        !_track.fx[index].bypass,
                      ),
                ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openFx,
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: Text(l10n.t('effectsTitle')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            SectionLabel(l10n.t('automationTitle')),
            Row(
              children: [
                Expanded(
                  child: Text(
                    automationPoints == 0
                        ? l10n.t('noPoints')
                        : l10n.t('pointsCount', {'count': automationPoints}),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openAutomation,
                  icon: const Icon(Icons.multiline_chart_rounded, size: 17),
                  label: Text(l10n.t('automationTitle')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
          ),
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(l10n.t('deleteTrack')),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textFaint,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textDim,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded, size: 16),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 28,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _FxRow extends StatelessWidget {
  const _FxRow({required this.slot, required this.onBypass});

  final FxSlot slot;
  final VoidCallback onBypass;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            slot.bypass ? Icons.power_off_rounded : Icons.auto_awesome_rounded,
            size: 15,
            color: slot.bypass ? AppColors.textFaint : AppColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              slot.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: slot.bypass ? AppColors.textFaint : AppColors.text,
              ),
            ),
          ),
          ToggleTag(
            label: 'B',
            active: slot.bypass,
            width: 24,
            height: 20,
            activeColor: AppColors.warning,
            tooltip: context.l10n.t('bypass'),
            onTap: onBypass,
          ),
        ],
      ),
    );
  }
}
