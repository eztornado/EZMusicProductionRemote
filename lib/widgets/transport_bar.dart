import 'package:flutter/material.dart';

import '../core/format.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/playhead_builder.dart';

class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConnection>(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        final enabled = connection.isConnected;
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundElevated,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              return compact
                  ? _CompactTransport(controller: controller, enabled: enabled)
                  : _WideTransport(controller: controller, enabled: enabled);
            },
          ),
        );
      },
    );
  }
}

class _WideTransport extends StatelessWidget {
  const _WideTransport({required this.controller, required this.enabled});

  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 220, child: _PositionDisplay(controller: controller)),
          const VerticalDivider(width: 24, indent: 8, endIndent: 8),
          _CoreButtons(controller: controller, enabled: enabled, large: true),
          const Spacer(),
          _TempoChip(controller: controller, enabled: enabled),
          const SizedBox(width: 8),
          _UtilityButtons(controller: controller, enabled: enabled),
        ],
      ),
    ).withSemantics(l10n.t('transport'));
  }
}

class _CompactTransport extends StatelessWidget {
  const _CompactTransport({required this.controller, required this.enabled});

  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _PositionDisplay(controller: controller, compact: true),
              ),
              const SizedBox(width: 8),
              _TempoChip(
                controller: controller,
                enabled: enabled,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _UtilityButtons(
                controller: controller,
                enabled: enabled,
                compact: true,
                includeMetronome: false,
              ),
              const Spacer(),
              _CoreButtons(
                controller: controller,
                enabled: enabled,
                large: false,
              ),
              const Spacer(),
              _MetronomeButton(controller: controller, enabled: enabled),
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionDisplay extends StatelessWidget {
  const _PositionDisplay({required this.controller, this.compact = false});

  final RemoteController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PlayheadBuilder(
      controller: controller,
      builder: (context, position) {
        return ValueListenableBuilder<TransportState>(
          valueListenable: controller.transport,
          builder: (context, state, _) {
            final tempo =
                state.tempoBpm > 0
                    ? state.tempoBpm
                    : (controller.currentProject?.tempoBpm ?? 120);
            final num = state.timeSigNum;
            final den = state.timeSigDen;
            return Row(
              children: [
                if (state.recording) ...[
                  const _RecordingPulse(),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatBarsBeats(
                          position,
                          bpm: tempo,
                          numerator: num,
                          denominator: den,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: compact ? 19 : 22,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                          color: AppColors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatClock(position)}  ·  ${formatClock(state.duration, showMillis: false)}',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: compact ? 9.5 : 10.5,
                          color: AppColors.textFaint,
                          letterSpacing: 0.3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
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

class _CoreButtons extends StatelessWidget {
  const _CoreButtons({
    required this.controller,
    required this.enabled,
    required this.large,
  });

  final RemoteController controller;
  final bool enabled;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<TransportState>(
      valueListenable: controller.transport,
      builder: (context, state, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TransportButton(
              icon: Icons.stop_rounded,
              tooltip: l10n.t('stop'),
              size: large ? 42 : 38,
              onPressed: enabled ? () => controller.stop() : null,
            ),
            const SizedBox(width: 6),
            _TransportButton(
              icon:
                  state.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
              tooltip: state.playing ? l10n.t('pause') : l10n.t('play'),
              size: large ? 50 : 46,
              primary: true,
              onPressed:
                  enabled
                      ? () =>
                          state.playing ? controller.pause() : controller.play()
                      : null,
            ),
            const SizedBox(width: 6),
            _RecordButton(
              recording: state.recording,
              size: large ? 42 : 38,
              onPressed: enabled ? () => controller.toggleRecord() : null,
            ),
          ],
        );
      },
    );
  }
}

class _UtilityButtons extends StatelessWidget {
  const _UtilityButtons({
    required this.controller,
    required this.enabled,
    this.compact = false,
    this.includeMetronome = true,
  });

  final RemoteController controller;
  final bool enabled;
  final bool compact;
  final bool includeMetronome;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: controller.project,
      builder: (context, project, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconButton(
              icon: Icons.undo_rounded,
              tooltip: context.l10n.t('undo'),
              minSize: compact ? 38 : 40,
              size: 19,
              onPressed:
                  enabled && (project?.canUndo ?? false)
                      ? () => controller.undo()
                      : null,
            ),
            if (!compact) const SizedBox(width: 2),
            AppIconButton(
              icon: Icons.redo_rounded,
              tooltip: context.l10n.t('redo'),
              minSize: compact ? 38 : 40,
              size: 19,
              onPressed:
                  enabled && (project?.canRedo ?? false)
                      ? () => controller.redo()
                      : null,
            ),
            if (includeMetronome) ...[
              const SizedBox(width: 8),
              _MetronomeButton(controller: controller, enabled: enabled),
            ],
          ],
        );
      },
    );
  }
}

class _MetronomeButton extends StatelessWidget {
  const _MetronomeButton({required this.controller, required this.enabled});

  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportState>(
      valueListenable: controller.transport,
      builder: (context, state, _) {
        return _TransportButton(
          icon: Icons.av_timer_rounded,
          tooltip: context.l10n.t('metronome'),
          active: state.metronome,
          size: 40,
          onPressed: enabled ? () => controller.toggleMetronome() : null,
        );
      },
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    this.onPressed,
    this.primary = false,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback? onPressed;
  final bool primary;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final background =
        primary
            ? (disabled ? AppColors.panelHigh : AppColors.accent)
            : active
            ? AppColors.accentSoft
            : AppColors.panel;
    final foreground =
        primary
            ? (disabled ? AppColors.textFaint : const Color(0xFF06121F))
            : disabled
            ? AppColors.textFaint.withValues(alpha: 0.5)
            : active
            ? AppColors.accent
            : AppColors.text;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: !disabled,
        child: InkResponse(
          onTap: onPressed,
          radius: size * 0.65,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border:
                  primary
                      ? null
                      : Border.all(
                        color:
                            active
                                ? AppColors.accent.withValues(alpha: 0.6)
                                : AppColors.border,
                      ),
              boxShadow:
                  primary && !disabled
                      ? [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.28),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ]
                      : null,
            ),
            child: Icon(icon, size: size * 0.52, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.size,
    required this.onPressed,
  });

  final bool recording;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = recording ? AppColors.record : AppColors.brand;
    return Tooltip(
      message: context.l10n.t(recording ? 'stopRecord' : 'record'),
      child: Semantics(
        button: true,
        toggled: recording,
        label: context.l10n.t(recording ? 'stopRecord' : 'record'),
        child: InkResponse(
          onTap: onPressed,
          radius: size * 0.65,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color:
                  recording ? color.withValues(alpha: 0.22) : AppColors.panel,
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: recording ? 0.8 : 0.45),
              ),
            ),
            child: Icon(
              recording
                  ? Icons.stop_rounded
                  : Icons.fiber_manual_record_rounded,
              size: size * (recording ? 0.48 : 0.4),
              color: recording ? color : AppColors.brand,
            ),
          ),
        ),
      ),
    );
  }
}

class _TempoChip extends StatelessWidget {
  const _TempoChip({
    required this.controller,
    required this.enabled,
    this.compact = false,
  });

  final RemoteController controller;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportState>(
      valueListenable: controller.transport,
      builder: (context, state, _) {
        final num = state.timeSigNum > 0 ? state.timeSigNum : 4;
        final den = state.timeSigDen > 0 ? state.timeSigDen : 4;
        return Tooltip(
          message: context.l10n.t('tempo'),
          child: InkWell(
            onTap: enabled ? () => showTempoSheet(context, controller) : null,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 6 : 7,
              ),
              decoration: panelDecoration(color: AppColors.panel, radius: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.tempoBpm.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Text(
                        'BPM',
                        style: TextStyle(
                          fontSize: 7.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 9),
                  Container(width: 1, height: 22, color: AppColors.border),
                  const SizedBox(width: 9),
                  Text(
                    '$num/$den',
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDim,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse();

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.35,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.record,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.record.withValues(alpha: 0.5),
              blurRadius: 7,
            ),
          ],
        ),
      ),
    );
  }
}

extension on Widget {
  Widget withSemantics(String label) {
    return Semantics(container: true, label: label, child: this);
  }
}

Future<void> showTempoSheet(BuildContext context, RemoteController controller) {
  return showAppSheet<void>(
    context,
    maxWidth: 520,
    builder: (ctx) => _TempoSheet(controller: controller),
  );
}

class _TempoSheet extends StatefulWidget {
  const _TempoSheet({required this.controller});

  final RemoteController controller;

  @override
  State<_TempoSheet> createState() => _TempoSheetState();
}

class _TempoSheetState extends State<_TempoSheet> {
  late double _bpm;
  late int _num;
  late int _den;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = widget.controller.transport.value;
    _bpm = state.tempoBpm > 0 ? state.tempoBpm : 120;
    _num = state.timeSigNum.clamp(1, 16).toInt();
    _den =
        const <int>[2, 4, 8, 16].contains(state.timeSigDen)
            ? state.timeSigDen
            : 4;
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    await widget.controller.setTempo(_bpm);
    await widget.controller.setTimeSignature(_num, _den);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        SheetHeader(
          title: l10n.t('tempo'),
          subtitle: l10n.t('timeSignature'),
          icon: Icons.speed_rounded,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: () => setState(() => _bpm = (_bpm - 1).clamp(20, 300)),
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 120,
              child: Text(
                _bpm.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 42,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                  color: AppColors.text,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _bpm = (_bpm + 1).clamp(20, 300)),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Slider(
          value: _bpm.clamp(20, 300).toDouble(),
          min: 20,
          max: 300,
          divisions: 280,
          label: '${_bpm.toStringAsFixed(0)} BPM',
          onChanged: (value) => setState(() => _bpm = value),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final value in <double>[60, 90, 120, 128, 140, 174])
              ChoiceChip(
                label: Text('${value.toInt()}'),
                selected: (_bpm - value).abs() < 0.01,
                onSelected: (_) => setState(() => _bpm = value),
                showCheckmark: false,
                backgroundColor: AppColors.panel,
                selectedColor: AppColors.accentSoft,
                side: const BorderSide(color: AppColors.border),
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.t('timeSignature')),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _num,
                dropdownColor: AppColors.panel,
                decoration: InputDecoration(labelText: l10n.t('timeSignature')),
                items: [
                  for (var value = 1; value <= 16; value++)
                    DropdownMenuItem(value: value, child: Text('$value')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _num = value);
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: 22,
                  color: AppColors.textFaint,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _den,
                dropdownColor: AppColors.panel,
                decoration: InputDecoration(labelText: '1/'),
                items: [
                  for (final value in <int>[2, 4, 8, 16])
                    DropdownMenuItem(value: value, child: Text('$value')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _den = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _apply,
          icon:
              _saving
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.check_rounded, size: 19),
          label: Text(l10n.t('apply')),
        ),
      ],
    );
  }
}
