import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/project.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/parameter_controls.dart';

/// Instrument-focused view.
///
/// The desktop EZSynth Studio exposes hundreds of parameters across pages, so
/// the remote reuses the same grouped paging model instead of a flat slider
/// list. Any instrument that publishes groups and programs benefits; EZSynth 2
/// additionally gets its badge and factory presets.
class SynthScreen extends StatelessWidget {
  const SynthScreen({super.key, required this.controller});

  final RemoteController controller;

  static bool _isEzSynth(String name) => name.toLowerCase().contains('ezsynth');

  /// Keeps a minimum content height so a landscape phone scrolls the whole
  /// panel instead of squeezing the parameter list or an empty state into a
  /// few pixels.
  static Widget _fill(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(constraints.maxHeight, 340.0);
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: controller.project,
      builder: (context, project, _) {
        if (project == null) {
          return _fill(
            EmptyState(
              icon: Icons.piano_rounded,
              title: l10n.t('connectionLost'),
              message: l10n.t('errorNotConnected'),
            ),
          );
        }
        return Column(
          children: [
            _SynthToolbar(controller: controller),
            TrackChips(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<int?>(
                valueListenable: controller.selectedTrackId,
                builder: (context, selectedId, _) {
                  final track = project.trackById(selectedId);
                  if (track == null || !track.isInstrument) {
                    final firstInstrument =
                        project.tracks
                            .where((item) => item.isInstrument)
                            .firstOrNull;
                    return _fill(
                      EmptyState(
                        icon: Icons.piano_rounded,
                        title: l10n.t('synthNoTrack'),
                        message: l10n.t('synthHint'),
                        action:
                            firstInstrument == null
                                ? null
                                : OutlinedButton.icon(
                                  onPressed:
                                      () => controller.selectTrack(
                                        firstInstrument.id,
                                      ),
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 17,
                                  ),
                                  label: Text(firstInstrument.name),
                                ),
                      ),
                    );
                  }
                  if (!track.hasInstrument) {
                    return _fill(
                      EmptyState(
                        icon: Icons.piano_off_rounded,
                        title: l10n.t('synthNoInstrument'),
                        message: l10n.t('synthHint'),
                      ),
                    );
                  }
                  return _fill(
                    _SynthBody(controller: controller, track: track),
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

class _SynthToolbar extends StatelessWidget {
  const _SynthToolbar({required this.controller});

  final RemoteController controller;

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
                Icons.piano_rounded,
                size: 17,
                color: AppColors.accent,
              ),
              const SizedBox(width: 7),
              Text(
                l10n.t('synthTitle'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 7),
              ValueListenableBuilder<RemoteProject?>(
                valueListenable: controller.project,
                builder: (context, project, _) {
                  final track = project?.trackById(
                    controller.selectedTrackId.value,
                  );
                  final name = track?.instrument.trim() ?? '';
                  return CountBadge(
                    name.isEmpty ? l10n.t('instrumentSection') : name,
                  );
                },
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.t('synthHint'),
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
              const SizedBox(width: 10),
            ],
          );
        },
      ),
    );
  }
}

class _SynthBody extends StatelessWidget {
  const _SynthBody({required this.controller, required this.track});

  final RemoteController controller;
  final RemoteTrack track;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    final ezsynth = SynthScreen._isEzSynth(track.instrument);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.26)),
                ),
                child: Icon(Icons.piano_rounded, size: 20, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.instrument,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (ezsynth) ...[
                          const SizedBox(width: 8),
                          CountBadge(
                            l10n.t('ezsynthBadge'),
                            color: AppColors.brandLight,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${track.name} · ${l10n.t('synthSubtitle')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ),
        Expanded(
          child: FxParameterView(
            key: ValueKey('synth-params-${track.id}-${track.instrument}'),
            controller: controller,
            trackId: track.id,
            slotKind: 1,
            slotIndex: 0,
            color: color,
            pageTabs: true,
          ),
        ),
      ],
    );
  }
}
