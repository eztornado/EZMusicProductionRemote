import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../l10n/strings.dart';
import '../../models/project.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/playhead_builder.dart';

Future<void> showClipSheet(
  BuildContext context, {
  required RemoteController controller,
  required int clipId,
}) {
  return showAppSheet<void>(
    context,
    maxWidth: 560,
    heightFactor: 0.92,
    builder: (ctx) => _ClipSheet(controller: controller, clipId: clipId),
  );
}

class _ClipSheet extends StatelessWidget {
  const _ClipSheet({required this.controller, required this.clipId});

  final RemoteController controller;
  final int clipId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: controller.project,
      builder: (context, project, _) {
        final clip = project?.clipById(clipId);
        final track = project?.trackForClip(clipId);
        if (clip == null || track == null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: l10n.t('errorNotFound'),
              message: l10n.t('selectClip'),
              compact: true,
            ),
          );
        }
        return _ClipEditor(
          key: ValueKey('clip-editor-${clip.id}'),
          controller: controller,
          clip: clip,
          track: track,
        );
      },
    );
  }
}

class _ClipEditor extends StatefulWidget {
  const _ClipEditor({
    super.key,
    required this.controller,
    required this.clip,
    required this.track,
  });

  final RemoteController controller;
  final RemoteClip clip;
  final RemoteTrack track;

  @override
  State<_ClipEditor> createState() => _ClipEditorState();
}

class _ClipEditorState extends State<_ClipEditor> {
  late final TextEditingController _start;
  late final TextEditingController _length;
  late final TextEditingController _offset;
  late final FocusNode _startFocus = FocusNode();
  late final FocusNode _lengthFocus = FocusNode();
  late final FocusNode _offsetFocus = FocusNode();

  late double _fadeIn = widget.clip.fadeIn;
  late double _fadeOut = widget.clip.fadeOut;
  late double _gainDb =
      gainToDb(widget.clip.gain).clamp(-40.0, 12.0).toDouble();
  bool _draggingFade = false;
  bool _draggingGain = false;

  RemoteController get _controller => widget.controller;
  RemoteClip get _clip => widget.clip;
  RemoteTrack get _track => widget.track;

  @override
  void initState() {
    super.initState();
    _start = TextEditingController(text: _formatSeconds(_clip.start));
    _length = TextEditingController(text: _formatSeconds(_clip.length));
    _offset = TextEditingController(text: _formatSeconds(_clip.offset));
    _startFocus.addListener(() {
      if (!_startFocus.hasFocus) _commitBounds();
    });
    _lengthFocus.addListener(() {
      if (!_lengthFocus.hasFocus) _commitBounds();
    });
    _offsetFocus.addListener(() {
      if (!_offsetFocus.hasFocus) _commitBounds();
    });
  }

  @override
  void didUpdateWidget(covariant _ClipEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_startFocus.hasFocus) {
      final text = _formatSeconds(widget.clip.start);
      if (_start.text != text) _start.text = text;
    }
    if (!_lengthFocus.hasFocus) {
      final text = _formatSeconds(widget.clip.length);
      if (_length.text != text) _length.text = text;
    }
    if (!_offsetFocus.hasFocus) {
      final text = _formatSeconds(widget.clip.offset);
      if (_offset.text != text) _offset.text = text;
    }
    if (!_draggingFade) {
      _fadeIn = widget.clip.fadeIn;
      _fadeOut = widget.clip.fadeOut;
    }
    if (!_draggingGain) {
      _gainDb = gainToDb(widget.clip.gain).clamp(-40.0, 12.0).toDouble();
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _length.dispose();
    _offset.dispose();
    _startFocus.dispose();
    _lengthFocus.dispose();
    _offsetFocus.dispose();
    super.dispose();
  }

  String _formatSeconds(double value) => value.toStringAsFixed(3);

  double _parse(TextEditingController controller, double fallback) {
    return double.tryParse(controller.text.trim()) ?? fallback;
  }

  double get _displayedStart =>
      _parse(_start, _clip.start).clamp(0.0, double.infinity).toDouble();

  double get _displayedLength =>
      _parse(_length, _clip.length).clamp(0.05, double.infinity).toDouble();

  double get _displayedOffset =>
      _parse(_offset, _clip.offset).clamp(0.0, double.infinity).toDouble();

  Future<void> _commitBounds() async {
    if (!mounted) return;
    final start = _displayedStart;
    final length = _displayedLength;
    final offset = _displayedOffset;
    if ((start - _clip.start).abs() < 0.0005 &&
        (length - _clip.length).abs() < 0.0005 &&
        (offset - _clip.offset).abs() < 0.0005) {
      return;
    }
    await _controller.setClipBounds(
      _clip.id,
      start: start,
      offset: offset,
      length: length,
    );
  }

  Future<void> _nudgeStart(double delta) async {
    final geometry = dragClipGeometry(
      start: _displayedStart,
      length: _displayedLength,
      offset: _displayedOffset,
      delta: delta,
    );
    _start.text = _formatSeconds(geometry.$1);
    _length.text = _formatSeconds(geometry.$2);
    _offset.text = _formatSeconds(geometry.$3);
    await _controller.setClipBounds(
      _clip.id,
      start: geometry.$1,
      offset: geometry.$3,
      length: geometry.$2,
    );
  }

  (double, double, double) dragClipGeometry({
    required double start,
    required double length,
    required double offset,
    required double delta,
  }) {
    final newStart = (start + delta).clamp(0.0, start + length - 0.05);
    var actual = newStart - start;
    final newOffset = (offset + actual).clamp(0.0, double.infinity);
    actual = newOffset - offset;
    return (start + actual, math.max(0.05, length - actual), newOffset);
  }

  Future<void> _nudgeLength(double delta) async {
    final length = (_displayedLength + delta).clamp(0.05, 3600.0).toDouble();
    _length.text = _formatSeconds(length);
    await _controller.setClipBounds(
      _clip.id,
      start: _displayedStart,
      offset: _displayedOffset,
      length: length,
    );
  }

  Future<void> _nudgeOffset(double delta) async {
    final offset = (_displayedOffset + delta).clamp(0.0, 3600.0).toDouble();
    _offset.text = _formatSeconds(offset);
    await _controller.setClipBounds(
      _clip.id,
      start: _displayedStart,
      offset: offset,
      length: _displayedLength,
    );
  }

  Future<void> _commitFades() async {
    _draggingFade = true;
    try {
      await _controller.setClipFades(_clip.id, _fadeIn, _fadeOut);
    } finally {
      _draggingFade = false;
    }
  }

  Future<void> _commitGain() async {
    _draggingGain = true;
    try {
      await _controller.setClipGain(_clip.id, dbToGain(_gainDb));
    } finally {
      _draggingGain = false;
    }
  }

  Future<void> _splitAtPlayhead(double position) async {
    final ok = await _controller.splitClip(_clip.id, position);
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _moveToPlayhead(double position) async {
    final ok = await _controller.moveClip(
      _clip.id,
      _track.id,
      math.max(0, position),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('deleteClip'),
      message:
          '${l10n.t('deleteClipConfirm')}\n\n${l10n.t('deleteClipConfirmDesc')}',
      confirmLabel: l10n.t('delete'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    final removed = await _controller.removeClip(_clip.id);
    if (removed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(_track.colorIndex);
    final maxFade = math.max(0.05, _clip.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        SheetHeader(
          title: _clip.isMidi ? l10n.t('midiClip') : l10n.t('audioClip'),
          subtitle: '${_track.name} · ${formatClock(_clip.length)}',
          icon: _clip.isMidi ? Icons.piano_rounded : Icons.graphic_eq_rounded,
        ),
        _ClipPreview(clip: _clip, color: color),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: panelDecoration(),
          child: Column(
            children: [
              InfoRow(
                label: l10n.t('clipStart'),
                value:
                    '${_formatSeconds(_clip.start)} ${l10n.t('secondsUnit')}',
                icon: Icons.play_arrow_rounded,
              ),
              InfoRow(
                label: l10n.t('clipLength'),
                value:
                    '${_formatSeconds(_clip.length)} ${l10n.t('secondsUnit')}',
                icon: Icons.straighten_rounded,
              ),
              InfoRow(
                label: l10n.t('clipOffset'),
                value:
                    '${_formatSeconds(_clip.offset)} ${l10n.t('secondsUnit')}',
                icon: Icons.content_cut_rounded,
              ),
              if (_clip.isMidi)
                InfoRow(
                  label: l10n.t('midiClip'),
                  value: l10n.t('notesCount', {'count': _clip.notes.length}),
                  icon: Icons.music_note_rounded,
                ),
              if (_clip.muted)
                InfoRow(
                  label: l10n.t('muted'),
                  value: l10n.t('on'),
                  icon: Icons.volume_off_rounded,
                  valueColor: AppColors.warning,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            SectionLabel(l10n.t('clipDetails')),
            _NumberField(
              label: l10n.t('clipStart'),
              controller: _start,
              focusNode: _startFocus,
              onSubmitted: (_) => _commitBounds(),
              onMinus: () => _nudgeStart(-0.1),
              onPlus: () => _nudgeStart(0.1),
            ),
            const SizedBox(height: 10),
            _NumberField(
              label: l10n.t('clipLength'),
              controller: _length,
              focusNode: _lengthFocus,
              onSubmitted: (_) => _commitBounds(),
              onMinus: () => _nudgeLength(-0.1),
              onPlus: () => _nudgeLength(0.1),
            ),
            const SizedBox(height: 10),
            _NumberField(
              label: l10n.t('clipOffset'),
              controller: _offset,
              focusNode: _offsetFocus,
              onSubmitted: (_) => _commitBounds(),
              onMinus: () => _nudgeOffset(-0.1),
              onPlus: () => _nudgeOffset(0.1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            SectionLabel(l10n.t('fadeIn')),
            _LabeledSlider(
              value: _fadeIn.clamp(0.0, maxFade).toDouble(),
              min: 0,
              max: maxFade,
              label: formatSeconds(_fadeIn, decimals: 2),
              onChanged:
                  (value) => setState(() {
                    _draggingFade = true;
                    _fadeIn = value;
                  }),
              onChangeEnd: (_) => _commitFades(),
            ),
            const SizedBox(height: 8),
            SectionLabel(l10n.t('fadeOut')),
            _LabeledSlider(
              value: _fadeOut.clamp(0.0, maxFade).toDouble(),
              min: 0,
              max: maxFade,
              label: formatSeconds(_fadeOut, decimals: 2),
              onChanged:
                  (value) => setState(() {
                    _draggingFade = true;
                    _fadeOut = value;
                  }),
              onChangeEnd: (_) => _commitFades(),
            ),
            const SizedBox(height: 8),
            SectionLabel(l10n.t('clipGain')),
            _LabeledSlider(
              value: _gainDb.clamp(-40.0, 12.0).toDouble(),
              min: -40,
              max: 12,
              label: '${_gainDb.toStringAsFixed(1)} ${l10n.t('decibels')}',
              onChanged:
                  (value) => setState(() {
                    _draggingGain = true;
                    _gainDb = value;
                  }),
              onChangeEnd: (_) => _commitGain(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PlayheadBuilder(
          controller: _controller,
          builder: (context, position) {
            final canSplit =
                position > _clip.start + 0.03 &&
                position < _clip.start + _clip.length - 0.03;
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            canSplit ? () => _splitAtPlayhead(position) : null,
                        icon: const Icon(Icons.content_cut_rounded, size: 17),
                        label: Text(l10n.t('splitAtPlayhead')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _moveToPlayhead(position),
                        icon: const Icon(Icons.near_me_rounded, size: 17),
                        label: Text(l10n.t('moveToPlayhead')),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.45)),
          ),
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(l10n.t('deleteClip')),
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              labelText: label,
              suffixText: l10n.t('secondsUnit'),
              isDense: true,
            ),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
        const SizedBox(width: 4),
        _StepButton(icon: Icons.add_rounded, onTap: onPlus),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.panelAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 17, color: AppColors.textDim),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
          width: 72,
          child: Text(
            label,
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

class _ClipPreview extends StatelessWidget {
  const _ClipPreview({required this.clip, required this.color});

  final RemoteClip clip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _ClipPreviewPainter(clip: clip, color: color),
      ),
    );
  }
}

class _ClipPreviewPainter extends CustomPainter {
  _ClipPreviewPainter({required this.clip, required this.color});

  final RemoteClip clip;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              color.withValues(alpha: 0.18),
              AppColors.background,
            ),
            AppColors.background,
          ],
        ).createShader(rect),
    );

    if (clip.isMidi && clip.notes.isNotEmpty) {
      final pitches = clip.notes.map((note) => note.pitch).toList()..sort();
      final minPitch = pitches.first;
      final maxPitch = pitches.last;
      final range = math.max(1, maxPitch - minPitch);
      final notePaint = Paint()..color = color.withValues(alpha: 0.85);
      for (final note in clip.notes) {
        final x = (note.start / math.max(0.0001, clip.length)) * size.width;
        final w = (note.length / math.max(0.0001, clip.length)) * size.width;
        final y =
            8 + (1 - (note.pitch - minPitch) / range) * (size.height - 16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x.clamp(0.0, size.width), y, math.max(1.5, w), 3),
            const Radius.circular(1.5),
          ),
          notePaint,
        );
      }
    } else if (!clip.isMidi) {
      final paint =
          Paint()
            ..color = color.withValues(alpha: 0.45)
            ..strokeWidth = 1.2;
      final center = size.height / 2;
      for (var x = 3.0; x < size.width; x += 4) {
        final t = x / math.max(1, size.width);
        final amp = (math.sin(t * 38 + clip.id) * 0.4 +
                math.sin(t * 11 + 3) * 0.25 +
                0.35)
            .abs()
            .clamp(0.06, 1.0);
        canvas.drawLine(
          Offset(x, center - size.height * amp * 0.38),
          Offset(x, center + size.height * amp * 0.38),
          paint,
        );
      }
    } else {
      final painter = TextPainter(
        text: TextSpan(
          text: 'MIDI',
          style: TextStyle(
            color: color.withValues(alpha: 0.5),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (size.width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
    }

    if (clip.fadeIn > 0) {
      final width = (clip.fadeIn / math.max(0.0001, clip.length)) * size.width;
      final path =
          Path()
            ..moveTo(0, 0)
            ..lineTo(width.clamp(0, size.width), 0)
            ..lineTo(0, size.height)
            ..close();
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }
    if (clip.fadeOut > 0) {
      final width = (clip.fadeOut / math.max(0.0001, clip.length)) * size.width;
      final path =
          Path()
            ..moveTo(size.width, 0)
            ..lineTo(size.width - width.clamp(0, size.width), 0)
            ..lineTo(size.width, size.height)
            ..close();
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ClipPreviewPainter oldDelegate) {
    return oldDelegate.clip != clip || oldDelegate.color != color;
  }
}
