import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'sheets/master_fx_sheet.dart';
import 'sheets/plugin_picker_sheet.dart';

class _FxTarget {
  const _FxTarget({required this.kind, required this.slot});

  final int kind;
  final FxSlot slot;
}

/// Insert-chain browser and parameter editor.
///
/// On a tablet the chain and the parameter editor sit side by side. On a phone
/// the parameter editor opens as a sheet so the sliders keep a useful size.
class FxScreen extends StatefulWidget {
  const FxScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<FxScreen> createState() => _FxScreenState();
}

class _FxScreenState extends State<FxScreen> {
  int? _selectedSlotKind;
  int? _selectedSlotIndex;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.selectedTrackId.addListener(_onTrackChanged);
  }

  @override
  void dispose() {
    _controller.selectedTrackId.removeListener(_onTrackChanged);
    super.dispose();
  }

  void _onTrackChanged() {
    if (!mounted) return;
    setState(() {
      _selectedSlotKind = null;
      _selectedSlotIndex = null;
    });
  }

  void _select(int kind, FxSlot slot) {
    setState(() {
      _selectedSlotKind = kind;
      _selectedSlotIndex = slot.index;
    });
  }

  _FxTarget? _targetFor(RemoteTrack track, int kind, int index) {
    if (kind == 1) {
      if (!track.isInstrument || !track.hasInstrument) return null;
      return _FxTarget(
        kind: 1,
        slot: FxSlot(index: 0, name: track.instrument, bypass: false),
      );
    }
    for (final slot in track.fx) {
      if (slot.index == index) return _FxTarget(kind: 0, slot: slot);
    }
    return null;
  }

  _FxTarget? _selectedTarget(RemoteTrack track) {
    final kind = _selectedSlotKind;
    final index = _selectedSlotIndex;
    if (kind == null || index == null) return null;
    return _targetFor(track, kind, index);
  }

  Future<void> _addEffect(RemoteTrack track) async {
    final plugin = await showPluginPicker(
      context,
      _controller,
      title: context.l10n.t('addEffect'),
    );
    if (plugin == null) return;
    await _controller.addFx(track.id, plugin.index);
  }

  Future<void> _removeEffect(RemoteTrack track, FxSlot slot) async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('removeEffect'),
      message: l10n.t('removeEffectConfirm', {'name': slot.name}),
      confirmLabel: l10n.t('remove'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    if (_selectedSlotKind == 0 && _selectedSlotIndex == slot.index) {
      setState(() {
        _selectedSlotKind = null;
        _selectedSlotIndex = null;
      });
    }
    await _controller.removeFx(track.id, slot.index);
  }

  Future<void> _openParams(RemoteTrack track, int slotKind, FxSlot slot) async {
    _select(slotKind, slot);
    await showAppSheet<void>(
      context,
      maxWidth: 580,
      heightFactor: 0.9,
      builder:
          (ctx) => ValueListenableBuilder<RemoteProject?>(
            valueListenable: _controller.project,
            builder: (ctx, project, _) {
              final liveTrack = project?.trackById(track.id);
              final liveTarget =
                  liveTrack == null
                      ? null
                      : _targetFor(liveTrack, slotKind, slot.index);
              if (liveTrack == null || liveTarget == null) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: ctx.l10n.t('errorNotFound'),
                    message: ctx.l10n.t('noPluginSelected'),
                    compact: true,
                  ),
                );
              }
              return _FxParamEditor(
                key: ValueKey(
                  'fx-param-sheet-${liveTrack.id}-$slotKind-${liveTarget.slot.index}',
                ),
                controller: _controller,
                track: liveTrack,
                slot: liveTarget.slot,
                slotKind: slotKind,
                sheet: true,
              );
            },
          ),
    );
  }

  Widget _wideContent(RemoteTrack track, L10n l10n) {
    final target = _selectedTarget(track);
    return Row(
      children: [
        SizedBox(
          width: 336,
          child: _FxChainPane(
            controller: _controller,
            track: track,
            selectedKind: _selectedSlotKind,
            selectedSlotIndex: _selectedSlotIndex,
            onSelect: _select,
            onAdd: () => _addEffect(track),
            onRemove: (next) => _removeEffect(track, next),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child:
              target == null
                  ? EmptyState(
                    icon: Icons.tune_rounded,
                    title: l10n.t('noPluginSelected'),
                    message: l10n.t('selectEffectPrompt'),
                  )
                  : _FxParamEditor(
                    key: ValueKey(
                      'fx-params-${track.id}-${target.kind}-${target.slot.index}',
                    ),
                    controller: _controller,
                    track: track,
                    slot: target.slot,
                    slotKind: target.kind,
                    sheet: false,
                  ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteProject?>(
      valueListenable: _controller.project,
      builder: (context, project, _) {
        if (project == null) {
          return EmptyState(
            icon: Icons.tune_rounded,
            title: l10n.t('connectionLost'),
            message: l10n.t('errorNotConnected'),
          );
        }
        return Column(
          children: [
            _FxToolbar(
              controller: _controller,
              onMaster: () => showMasterFxSheet(context, _controller),
            ),
            TrackChips(controller: _controller),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<int?>(
                valueListenable: _controller.selectedTrackId,
                builder: (context, selectedId, _) {
                  final track = project.trackById(selectedId);
                  if (track == null) {
                    return EmptyState(
                      icon: Icons.tune_rounded,
                      title: l10n.t('fxNoTrack'),
                      message: l10n.t('selectTrack'),
                      action:
                          project.tracks.isEmpty
                              ? null
                              : OutlinedButton.icon(
                                onPressed:
                                    () => _controller.selectTrack(
                                      project.tracks.first.id,
                                    ),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 17,
                                ),
                                label: Text(project.tracks.first.name),
                              ),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      // Keep the chain usable on short landscape screens by
                      // scrolling the whole pane instead of squeezing fixed
                      // headers and buttons into a few pixels.
                      final contentHeight = math.max(
                        constraints.maxHeight,
                        300.0,
                      );
                      final content =
                          wide
                              ? _wideContent(track, l10n)
                              : _FxChainPane(
                                controller: _controller,
                                track: track,
                                selectedKind: _selectedSlotKind,
                                selectedSlotIndex: _selectedSlotIndex,
                                onSelect:
                                    (kind, slot) =>
                                        _openParams(track, kind, slot),
                                onAdd: () => _addEffect(track),
                                onRemove: (slot) => _removeEffect(track, slot),
                              );
                      return SingleChildScrollView(
                        child: SizedBox(height: contentHeight, child: content),
                      );
                    },
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

class _FxToolbar extends StatelessWidget {
  const _FxToolbar({required this.controller, required this.onMaster});

  final RemoteController controller;
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
              const Icon(Icons.tune_rounded, size: 17, color: AppColors.accent),
              const SizedBox(width: 7),
              Text(
                l10n.t('effectsTitle'),
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
                  final selected = controller.selectedTrackId.value;
                  final track = project?.trackById(selected);
                  return CountBadge(
                    l10n.t('fxSlots', {'count': track?.fx.length ?? 0}),
                  );
                },
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.t('fxHint'),
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
              if (wide)
                TextButton.icon(
                  onPressed: onMaster,
                  icon: const Icon(
                    Icons.surround_sound_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  label: Text(l10n.t('masterFx')),
                )
              else
                AppIconButton(
                  icon: Icons.surround_sound_rounded,
                  tooltip: l10n.t('masterFx'),
                  onPressed: onMaster,
                  minSize: 36,
                  size: 18,
                  color: AppColors.warning,
                ),
              const SizedBox(width: 6),
            ],
          );
        },
      ),
    );
  }
}

class _FxChainPane extends StatelessWidget {
  const _FxChainPane({
    required this.controller,
    required this.track,
    required this.selectedKind,
    required this.selectedSlotIndex,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
  });

  final RemoteController controller;
  final RemoteTrack track;
  final int? selectedKind;
  final int? selectedSlotIndex;
  final void Function(int kind, FxSlot slot) onSelect;
  final VoidCallback onAdd;
  final ValueChanged<FxSlot> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      track.isInstrument
                          ? (track.hasInstrument
                              ? track.instrument
                              : l10n.t('instrumentSection'))
                          : l10n.t('insertEffects'),
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
              CountBadge(
                l10n.t('fxSlots', {'count': track.fx.length}),
                color: color,
              ),
            ],
          ),
        ),
        if (track.isInstrument && track.hasInstrument) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _InstrumentCard(
              name: track.instrument,
              midiFx: track.midiFx,
              color: color,
              selected: selectedKind == 1,
              onTap:
                  () => onSelect(
                    1,
                    FxSlot(index: 0, name: track.instrument, bypass: false),
                  ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(l10n.t('addEffect')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(38),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              track.fx.isEmpty
                  ? EmptyState(
                    icon: Icons.auto_awesome_rounded,
                    title: l10n.t('noEffects'),
                    message: l10n.t('fxHint'),
                    compact: true,
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                    itemCount: track.fx.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final slot = track.fx[index];
                      return _FxCard(
                        slot: slot,
                        color: color,
                        selected:
                            selectedKind == 0 &&
                            selectedSlotIndex == slot.index,
                        onTap: () => onSelect(0, slot),
                        onBypass:
                            () => controller.setFxBypass(
                              track.id,
                              slot.index,
                              !slot.bypass,
                            ),
                        onRemove: () => onRemove(slot),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({
    required this.name,
    required this.midiFx,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String midiFx;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color:
                selected
                    ? Color.alphaBlend(
                      AppColors.accent.withValues(alpha: 0.07),
                      AppColors.surface,
                    )
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.65) : AppColors.border,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.piano_rounded, size: 15, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      midiFx.trim().isEmpty
                          ? l10n.t('instrumentParameters')
                          : '${l10n.t('midiFxLabel')}: $midiFx',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FxCard extends StatelessWidget {
  const _FxCard({
    required this.slot,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.onBypass,
    required this.onRemove,
  });

  final FxSlot slot;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onBypass;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
          decoration: BoxDecoration(
            color:
                selected
                    ? Color.alphaBlend(
                      AppColors.accent.withValues(alpha: 0.07),
                      AppColors.surface,
                    )
                    : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected ? color.withValues(alpha: 0.65) : AppColors.border,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      slot.bypass
                          ? AppColors.panelAlt
                          : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${slot.index + 1}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: slot.bypass ? AppColors.textFaint : color,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            slot.bypass ? AppColors.textFaint : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      slot.bypass ? l10n.t('bypass') : l10n.t('enabled'),
                      style: TextStyle(
                        fontSize: 8.5,
                        color:
                            slot.bypass
                                ? AppColors.textFaint
                                : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              ToggleTag(
                label: 'B',
                active: slot.bypass,
                width: 24,
                height: 21,
                activeColor: AppColors.warning,
                tooltip: l10n.t('bypass'),
                onTap: onBypass,
              ),
              IconButton(
                tooltip: l10n.t('removeEffect'),
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                visualDensity: VisualDensity.compact,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FxParamEditor extends StatefulWidget {
  const _FxParamEditor({
    super.key,
    required this.controller,
    required this.track,
    required this.slot,
    required this.slotKind,
    required this.sheet,
  });

  final RemoteController controller;
  final RemoteTrack track;
  final FxSlot slot;
  final int slotKind;
  final bool sheet;

  @override
  State<_FxParamEditor> createState() => _FxParamEditorState();
}

class _FxParamEditorState extends State<_FxParamEditor> {
  final TextEditingController _search = TextEditingController();
  final Map<int, double> _values = <int, double>{};
  final Map<int, String> _texts = <int, String>{};
  final Map<int, double> _pending = <int, double>{};
  Timer? _flushTimer;
  List<FxParam> _params = const <FxParam>[];
  bool _loading = true;
  String? _error;
  String _query = '';

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flush();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final params = await _controller.fetchFxParams(
        trackId: widget.track.id,
        slotKind: widget.slotKind,
        slotIndex: widget.slot.index,
      );
      if (!mounted) return;
      setState(() {
        _params = params;
        _values
          ..clear()
          ..addEntries(
            params.map((param) => MapEntry(param.index, param.value)),
          );
        _texts
          ..clear()
          ..addEntries(
            params.map((param) => MapEntry(param.index, param.text)),
          );
        _loading = false;
      });
    } on Object catch (raw) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$raw';
      });
    }
  }

  void _queue(int index, double value) {
    _values[index] = value;
    _pending[index] = value;
    _flushTimer ??= Timer(const Duration(milliseconds: 65), _flush);
  }

  void _commit(int index, double value) {
    _values[index] = value;
    _pending[index] = value;
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final batch = Map<int, double>.from(_pending);
    _pending.clear();
    for (final entry in batch.entries) {
      unawaited(
        _controller
            .setFxParam(
              trackId: widget.track.id,
              slotKind: widget.slotKind,
              slotIndex: widget.slot.index,
              paramIndex: entry.key,
              value: entry.value,
            )
            .then((param) {
              if (param == null || !mounted) return;
              setState(() {
                _values[entry.key] = param.value;
                _texts[entry.key] = param.text;
              });
            }),
      );
    }
  }

  List<FxParam> get _filtered {
    if (_query.isEmpty) return _params;
    final needle = _query.toLowerCase();
    return _params
        .where((param) => param.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(widget.track.colorIndex);
    final filtered = _filtered;
    return Column(
      children: [
        _ParamHeader(
          track: widget.track,
          slot: widget.slot,
          slotKind: widget.slotKind,
          sheet: widget.sheet,
          loading: _loading,
          onReload: _load,
          onBypass:
              () => _controller.setFxBypass(
                widget.track.id,
                widget.slot.index,
                !widget.slot.bypass,
              ),
        ),
        if (!_loading && _params.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: l10n.t('searchParameters'),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon:
                    _query.isEmpty
                        ? null
                        : IconButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 17),
                        ),
              ),
            ),
          ),
        Expanded(
          child:
              _loading
                  ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                  : _error != null
                  ? EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: l10n.t('error'),
                    message: l10n.t('errorCommandFailed', {'error': _error!}),
                    action: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: Text(l10n.t('retry')),
                    ),
                  )
                  : _params.isEmpty
                  ? EmptyState(
                    icon: Icons.tune_rounded,
                    title: l10n.t('noParameters'),
                    message: l10n.t('noPluginSelected'),
                    compact: true,
                  )
                  : filtered.isEmpty
                  ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.t('pluginListEmpty'),
                    message: l10n.t('searchParameters'),
                    compact: true,
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final param = filtered[index];
                      final value =
                          (_values[param.index] ?? param.value)
                              .clamp(0.0, 1.0)
                              .toDouble();
                      final text = _texts[param.index] ?? '';
                      return _ParamRow(
                        param: param,
                        value: value,
                        text: text.isEmpty ? '${(value * 100).round()}%' : text,
                        color: color,
                        bypass: widget.slot.bypass,
                        onChanged:
                            (next) => setState(() => _queue(param.index, next)),
                        onChangeEnd: (next) => _commit(param.index, next),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class _ParamHeader extends StatelessWidget {
  const _ParamHeader({
    required this.track,
    required this.slot,
    required this.slotKind,
    required this.sheet,
    required this.loading,
    required this.onReload,
    required this.onBypass,
  });

  final RemoteTrack track;
  final FxSlot slot;
  final int slotKind;
  final bool sheet;
  final bool loading;
  final VoidCallback onReload;
  final VoidCallback onBypass;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = AppColors.track(track.colorIndex);
    return Padding(
      padding: EdgeInsets.fromLTRB(sheet ? 20 : 16, sheet ? 4 : 14, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(Icons.tune_rounded, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slot.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${track.name} · ${l10n.t('parameters')}'
                  '${slot.bypass ? ' · ${l10n.t('bypass')}' : ''}',
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
          if (loading)
            const Padding(
              padding: EdgeInsets.all(10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            )
          else
            IconButton(
              tooltip: l10n.t('reloadPlugins'),
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          if (slotKind == 0)
            ToggleTag(
              label: 'B',
              active: slot.bypass,
              width: 26,
              height: 22,
              activeColor: AppColors.warning,
              tooltip: l10n.t('bypass'),
              onTap: onBypass,
            ),
          if (sheet)
            IconButton(
              tooltip: l10n.t('close'),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.param,
    required this.value,
    required this.text,
    required this.color,
    required this.bypass,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final FxParam param;
  final double value;
  final String text;
  final Color color;
  final bool bypass;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: bypass ? 0.62 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    param.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: AppColors.text,
                overlayColor: color.withValues(alpha: 0.14),
                trackHeight: 3,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: 1,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
