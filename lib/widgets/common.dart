import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.tile = true});

  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0B),
        borderRadius: BorderRadius.circular(size * 0.26),
        border:
            tile
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.22),
            blurRadius: size * 0.5,
            spreadRadius: -size * 0.15,
          ),
        ],
      ),
      child: CustomPaint(painter: _BrandPainter()),
    );
  }
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bars = <double>[0.44, 0.8, 0.58, 1.0, 0.5];
    final gap = size.width * 0.075;
    final barWidth = size.width * 0.095;
    final total = bars.length * barWidth + (bars.length - 1) * gap;
    var x = (size.width - total) / 2;
    final gradient = const LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [AppColors.brand, AppColors.brandLight],
    ).createShader(Offset.zero & size);
    final paint = Paint()..shader = gradient;
    final heights = <double>[0.44, 0.8, 0.58, 1.0, 0.5];
    for (final fraction in heights) {
      final height = size.height * 0.58 * fraction + size.height * 0.1;
      final top = (size.height - height) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, height),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
      x += barWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ArtistName extends StatelessWidget {
  const ArtistName({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'EZ',
          style: TextStyle(
            fontSize: compact ? 18 : 24,
            height: 0.95,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: AppColors.text,
          ),
        ),
        Text(
          'REMOTE',
          style: TextStyle(
            fontSize: compact ? 8 : 10,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: compact ? 2.6 : 3.6,
            color: AppColors.brandLight,
          ),
        ),
      ],
    );
  }
}

class StudioBackdrop extends StatelessWidget {
  const StudioBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.75, -0.9),
              radius: 1.35,
              colors: [Color(0xFF25201F), AppColors.background],
              stops: [0, 0.62],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _BackdropPainter())),
        ),
        child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.025)
          ..strokeWidth = 1;
    final step = math.max(32.0, size.width / 22);
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final wave =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.brand.withValues(alpha: 0.13);
    final path = Path();
    final baseline = size.height * 0.68;
    final amplitude = size.height * 0.11;
    for (var x = 0.0; x <= size.width; x += 4) {
      final t = x / size.width;
      final y =
          baseline +
          math.sin(t * math.pi * 7 + 0.8) * amplitude * (0.35 + t * 0.65) +
          math.sin(t * math.pi * 17) * amplitude * 0.15;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, wave);

    final glow =
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.brand.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.15, size.height * 0.05),
              radius: size.width * 0.65,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.05),
      size.width * 0.65,
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color = AppColors.success,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: dense ? 11 : 12, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key, this.trailing, this.padding});

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textFaint,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.color,
    this.size = 20,
    this.minSize = 40,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;
  final double size;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        onPressed == null
            ? AppColors.textFaint.withValues(alpha: 0.45)
            : active
            ? AppColors.accent
            : color ?? AppColors.textDim;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: minSize / 2,
        containedInkWell: true,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
          alignment: Alignment.center,
          decoration:
              active
                  ? BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.45),
                    ),
                  )
                  : null,
          child: Icon(icon, size: size, color: effectiveColor),
        ),
      ),
    );
  }
}

class ToggleTag extends StatelessWidget {
  const ToggleTag({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor = AppColors.accent,
    this.tooltip,
    this.width,
    this.height = 24,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color activeColor;
  final String? tooltip;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final body = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              active ? activeColor.withValues(alpha: 0.2) : AppColors.panelAlt,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color:
                active ? activeColor.withValues(alpha: 0.7) : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: active ? activeColor : AppColors.textFaint,
          ),
        ),
      ),
    );
    if (tooltip == null) return body;
    return Tooltip(message: tooltip!, child: body);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 44 : 58,
              height: compact ? 44 : 58,
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                icon,
                color: AppColors.textFaint,
                size: compact ? 22 : 28,
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 13,
                  height: 1.45,
                  color: AppColors.textDim,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 9),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge(this.text, {super.key, this.color = AppColors.textDim});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.borderStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 6, 12, 12),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: context.l10n.t('close'),
          ),
        ],
      ),
    );
  }
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 780,
  double heightFactor = 0.9,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.66),
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: media.size.height * heightFactor,
            ),
            child: Container(
              margin: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundElevated,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border.all(color: AppColors.borderStrong),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 30,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SheetHandle(),
                    Flexible(child: builder(ctx)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool danger = false,
  IconData icon = Icons.warning_amber_rounded,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder:
        (ctx) => Dialog(
          backgroundColor: AppColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.borderStrong),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: (danger ? AppColors.danger : AppColors.warning)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: danger ? AppColors.danger : AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.t('cancel')),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              danger ? AppColors.danger : AppColors.accent,
                          foregroundColor:
                              danger ? Colors.white : const Color(0xFF06121F),
                          minimumSize: const Size(40, 42),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(confirmLabel ?? l10n.t('confirm')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
  );
  return result ?? false;
}

String friendlyConnectionError(L10n l10n, RemoteConnection connection) {
  final raw = connection.message?.toLowerCase() ?? '';
  if (connection.phase == ConnectionPhase.authFailed) {
    return l10n.t('wrongCode');
  }
  if (raw.contains('refused')) return l10n.t('connectionRefused');
  if (raw.contains('timed out') || raw.contains('timeout')) {
    return l10n.t('connectionTimeout');
  }
  if (raw.contains('not found') || raw.contains('failed host lookup')) {
    return l10n.t('unknownHost');
  }
  if (connection.message != null && connection.message!.trim().isNotEmpty) {
    return connection.message!;
  }
  return l10n.t('connectionFailed');
}

String friendlyCommandError(L10n l10n, UiError error) {
  final code = error.code;
  final key = switch (code) {
    'not_connected' => 'errorNotConnected',
    'timeout' => 'errorTimeout',
    'auth_failed' => 'errorAuthFailed',
    'auth_required' => 'errorAuthRequired',
    'bad_request' => 'errorBadRequest',
    'invalid_argument' => 'errorInvalidArgument',
    'not_found' => 'errorNotFound',
    'unknown_command' => 'errorUnknownCommand',
    'audio_device' => 'errorAudioDevice',
    'record_failed' => 'errorRecordFailed',
    'bad_json' => 'errorBadJson',
    'socket' => 'errorSocket',
    'errorNoToken' => 'errorNoToken',
    _ => null,
  };
  if (key != null) return l10n.t(key);
  if (error.code == 'unexpected') {
    return l10n.t('errorUnexpected', {'error': error.message});
  }
  return l10n.t('errorUnexpected', {'error': error.message});
}

String relativeTime(DateTime time, L10n l10n) {
  if (time.millisecondsSinceEpoch <= 0) return l10n.t('unknown');
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final diff = today.difference(date).inDays;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (diff == 0) return '$hh:$mm';
  if (diff == 1) return '${l10n.t('yesterday')} $hh:$mm';
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')} $hh:$mm';
}

class TrackColorDot extends StatelessWidget {
  const TrackColorDot({
    super.key,
    required this.colorIndex,
    this.size = 8,
    this.glow = false,
  });

  final int colorIndex;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.track(colorIndex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow:
            glow
                ? [
                  BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
                ]
                : null,
      ),
    );
  }
}

class TrackChips extends StatelessWidget {
  const TrackChips({
    super.key,
    required this.controller,
    this.includeMaster = false,
    this.onMaster,
    this.masterSelected = false,
  });

  final RemoteController controller;
  final bool includeMaster;
  final VoidCallback? onMaster;
  final bool masterSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder(
      valueListenable: controller.project,
      builder: (context, project, _) {
        if (project == null) return const SizedBox.shrink();
        return ValueListenableBuilder<int?>(
          valueListenable: controller.selectedTrackId,
          builder: (context, selected, _) {
            return SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (includeMaster) ...[
                    _TrackChip(
                      label: l10n.t('master'),
                      selected: masterSelected,
                      color: AppColors.warning,
                      icon: Icons.surround_sound_rounded,
                      onTap: onMaster,
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (final track in project.tracks) ...[
                    _TrackChip(
                      label: track.name,
                      selected: !masterSelected && track.id == selected,
                      color: AppColors.track(track.colorIndex),
                      icon:
                          track.isInstrument
                              ? Icons.piano_rounded
                              : Icons.graphic_eq_rounded,
                      onTap: () => controller.selectTrack(track.id),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TrackChip extends StatelessWidget {
  const _TrackChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.panelHigh : AppColors.panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.7) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? color : AppColors.textFaint),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.text : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
