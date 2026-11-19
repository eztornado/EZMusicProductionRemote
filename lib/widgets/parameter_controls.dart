import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Group/page helpers shared by the FX editor and the instrument view.
///
/// The studio sends stable raw tokens (`a`, `f1`, `env`, …) instead of
/// translated labels. Keeping the mapping here means the same EZSynth pages
/// appear wherever a plugin is edited.
String parameterPageForGroup(String group) {
  final key = group.trim().toLowerCase();
  if (key.isEmpty) return 'all';
  if (key == 'f1' || key == 'f2' || key == 'filter') return 'filters';
  if (key.startsWith('e') && key.length == 2) return 'env';
  if (key.startsWith('l') && key.length == 2) return 'mod';
  if (key == 'rnd' || key == 'random' || key == 'm' || key == 'matrix') {
    return 'mod';
  }
  if (key == 'macro' || key == 'macros') return 'macro';
  if (key == 'mpe' || key == 'lines' || key == 'motion') return 'expr';
  if (key == 'filters' ||
      key == 'env' ||
      key == 'mod' ||
      key == 'fx' ||
      key == 'arp' ||
      key == 'expr' ||
      key == 'global' ||
      key == 'a' ||
      key == 'b' ||
      key == 'x' ||
      key == 'all') {
    return key;
  }
  return 'other:$key';
}

int parameterPageRank(String page) {
  const order = <String>[
    'global',
    'a',
    'b',
    'x',
    'filters',
    'env',
    'mod',
    'fx',
    'arp',
    'macro',
    'expr',
    'all',
  ];
  final index = order.indexOf(page);
  return index < 0 ? order.length : index;
}

String parameterPageLabel(L10n l10n, String page) {
  if (page.startsWith('other:')) {
    return _titleCase(page.substring(6));
  }
  return switch (page) {
    'global' => l10n.t('parameterGroupGlobal'),
    'a' => l10n.t('parameterGroupLayerA'),
    'b' => l10n.t('parameterGroupLayerB'),
    'x' => l10n.t('parameterGroupAux'),
    'filters' => l10n.t('parameterGroupFilters'),
    'env' => l10n.t('parameterGroupEnvelopes'),
    'mod' => l10n.t('parameterGroupModulation'),
    'fx' => l10n.t('parameterGroupFx'),
    'arp' => l10n.t('parameterGroupArp'),
    'macro' => l10n.t('parameterGroupMacros'),
    'expr' => l10n.t('parameterGroupExpression'),
    'all' => l10n.t('parameterGroupAll'),
    _ => l10n.t('parameterGroupOther'),
  };
}

String parameterGroupLabel(L10n l10n, String group, {bool allGroups = false}) {
  final key = group.trim().toLowerCase();
  if (key.isEmpty) {
    return allGroups
        ? l10n.t('parameterGroupAll')
        : l10n.t('parameterGroupOther');
  }
  return switch (key) {
    'global' => l10n.t('parameterGroupGlobal'),
    'a' => l10n.t('parameterGroupLayerA'),
    'b' => l10n.t('parameterGroupLayerB'),
    'x' => l10n.t('parameterGroupAux'),
    'f1' => l10n.t('groupFilter1'),
    'f2' => l10n.t('groupFilter2'),
    'e1' => l10n.t('groupEnv1'),
    'e2' => l10n.t('groupEnv2'),
    'e3' => l10n.t('groupEnv3'),
    'e4' => l10n.t('groupEnv4'),
    'l1' => l10n.t('groupLfo1'),
    'l2' => l10n.t('groupLfo2'),
    'l3' => l10n.t('groupLfo3'),
    'l4' => l10n.t('groupLfo4'),
    'rnd' || 'random' => l10n.t('groupRandom'),
    'm' || 'matrix' => l10n.t('groupMatrix'),
    'macro' || 'macros' => l10n.t('groupMacro'),
    'lines' || 'motion' => l10n.t('groupLines'),
    'mpe' => l10n.t('parameterGroupExpression'),
    'master' => l10n.t('groupMaster'),
    'fx' => l10n.t('parameterGroupFx'),
    'arp' => l10n.t('parameterGroupArp'),
    _ => _titleCase(group),
  };
}

String _titleCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return value;
  return '${trimmed.substring(0, 1).toUpperCase()}${trimmed.substring(1)}';
}

/// Page tabs are the interaction model of the desktop EZSynth Studio. On a
/// phone they keep hundreds of parameters navigable while the FX editor keeps
/// its plain grouped list.
class FxParameterView extends StatefulWidget {
  const FxParameterView({
    super.key,
    required this.controller,
    required this.trackId,
    required this.slotKind,
    required this.slotIndex,
    required this.color,
    this.bypass = false,
    this.showSearch = true,
    this.pageTabs = false,
    this.showPresets = true,
    this.compact = false,
    this.emptyMessage,
    this.onProgramChanged,
    this.refreshToken = 0,
  });

  final RemoteController controller;
  final int trackId;
  final int slotKind;
  final int slotIndex;
  final Color color;
  final bool bypass;
  final bool showSearch;
  final bool pageTabs;
  final bool showPresets;
  final bool compact;
  final String? emptyMessage;
  final ValueChanged<FxProgram>? onProgramChanged;

  /// Bump this value to force a fresh `fx.params` request.
  final int refreshToken;

  @override
  State<FxParameterView> createState() => _FxParameterViewState();
}

class _FxParameterViewState extends State<FxParameterView> {
  final TextEditingController _search = TextEditingController();
  final Map<int, double> _values = <int, double>{};
  final Map<int, String> _texts = <int, String>{};
  final Map<int, double> _pending = <int, double>{};
  Timer? _flushTimer;

  FxSlotSnapshot? _snapshot;
  String _query = '';
  String _page = 'all';
  bool _loading = true;
  bool _applyingProgram = false;
  String? _error;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant FxParameterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId ||
        oldWidget.slotKind != widget.slotKind ||
        oldWidget.slotIndex != widget.slotIndex ||
        oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load());
    }
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
      final snapshot = await _controller.fetchFxSlot(
        trackId: widget.trackId,
        slotKind: widget.slotKind,
        slotIndex: widget.slotIndex,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _values
          ..clear()
          ..addEntries(
            snapshot.params.map((param) => MapEntry(param.index, param.value)),
          );
        _texts
          ..clear()
          ..addEntries(
            snapshot.params.map((param) => MapEntry(param.index, param.text)),
          );
        _loading = false;
        final pages = _pagesFor(snapshot.params);
        if (pages.isNotEmpty && !pages.any((page) => page.key == _page)) {
          _page = pages.first.key;
        }
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

  void _reset(FxParam param) => _commit(param.index, param.defaultValue);

  void _flush() {
    if (_pending.isEmpty) return;
    final batch = Map<int, double>.from(_pending);
    _pending.clear();
    for (final entry in batch.entries) {
      unawaited(
        _controller
            .setFxParam(
              trackId: widget.trackId,
              slotKind: widget.slotKind,
              slotIndex: widget.slotIndex,
              paramIndex: entry.key,
              value: entry.value,
            )
            .then((param) {
              if (param == null || !mounted) return;
              setState(() {
                _values[entry.key] = param.value;
                if (param.text.isNotEmpty) _texts[entry.key] = param.text;
              });
            }),
      );
    }
  }

  Future<void> _applyProgram(int index) async {
    if (_applyingProgram) return;
    setState(() => _applyingProgram = true);
    final program = await _controller.setFxProgram(
      trackId: widget.trackId,
      slotKind: widget.slotKind,
      slotIndex: widget.slotIndex,
      programIndex: index,
    );
    if (!mounted) return;
    setState(() => _applyingProgram = false);
    if (program == null) return;
    widget.onProgramChanged?.call(program);
    final l10n = context.l10n;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(l10n.t('presetApplied', {'name': program.name}))),
    );
    await _load();
  }

  Future<void> _showPresetPicker() async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.hasPrograms) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (ctx) => _PresetPickerSheet(
            programs: snapshot.programs,
            current: snapshot.currentProgram,
          ),
    );
    if (selected != null && selected != snapshot.currentProgram) {
      await _applyProgram(selected);
    }
  }

  List<_ParameterPage> _pagesFor(List<FxParam> params) {
    final buckets = <String, List<FxParam>>{};
    for (final param in params) {
      final page = parameterPageForGroup(param.group);
      buckets.putIfAbsent(page, () => <FxParam>[]).add(param);
    }
    final pages =
        buckets.entries
            .map((entry) => _ParameterPage(key: entry.key, params: entry.value))
            .toList();
    pages.sort((a, b) {
      final rank = parameterPageRank(a.key).compareTo(parameterPageRank(b.key));
      return rank != 0 ? rank : a.key.compareTo(b.key);
    });
    return pages;
  }

  List<_ParameterSection> _sectionsFor(List<FxParam> params) {
    final buckets = <String, List<FxParam>>{};
    for (final param in params) {
      final key = param.group.trim();
      buckets.putIfAbsent(key, () => <FxParam>[]).add(param);
    }
    final sections =
        buckets.entries
            .map(
              (entry) => _ParameterSection(key: entry.key, params: entry.value),
            )
            .toList();
    sections.sort((a, b) {
      final rank = parameterPageRank(
        parameterPageForGroup(a.key),
      ).compareTo(parameterPageRank(parameterPageForGroup(b.key)));
      return rank != 0 ? rank : a.key.compareTo(b.key);
    });
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = _snapshot;
    final params = snapshot?.params ?? const <FxParam>[];
    final needle = _query.trim().toLowerCase();
    final filtered =
        needle.isEmpty
            ? params
            : params
                .where(
                  (param) =>
                      param.name.toLowerCase().contains(needle) ||
                      param.id.toLowerCase().contains(needle) ||
                      parameterGroupLabel(
                        l10n,
                        param.group,
                        allGroups: params.every(
                          (item) => item.group.trim().isEmpty,
                        ),
                      ).toLowerCase().contains(needle),
                )
                .toList(growable: false);
    final pages = _pagesFor(filtered);
    final allGroups = params.every((param) => param.group.trim().isEmpty);
    final activePage =
        needle.isNotEmpty
            ? null
            : pages.where((page) => page.key == _page).firstOrNull ??
                pages.firstOrNull;
    final visible = activePage?.params ?? filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot != null && snapshot.hasPrograms && widget.showPresets) ...[
          _PresetBar(
            programs: snapshot.programs,
            current: snapshot.currentProgram,
            busy: _applyingProgram,
            onBrowse: _showPresetPicker,
          ),
          const SizedBox(height: 8),
        ],
        if (widget.showSearch && !_loading && params.length > 5)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 14 : 16,
              0,
              widget.compact ? 14 : 16,
              8,
            ),
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
        if (widget.pageTabs && needle.isEmpty && pages.length > 1)
          _PageTabs(
            pages: pages,
            selected: activePage?.key ?? pages.first.key,
            labelFor: (page) => parameterPageLabel(l10n, page),
            onSelected: (page) => setState(() => _page = page),
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
                  : params.isEmpty
                  ? EmptyState(
                    icon: Icons.tune_rounded,
                    title: l10n.t('noParameters'),
                    message: widget.emptyMessage ?? l10n.t('noPluginSelected'),
                    compact: true,
                  )
                  : filtered.isEmpty
                  ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: l10n.t('pluginListEmpty'),
                    message: l10n.t('searchParameters'),
                    compact: true,
                  )
                  : _ParameterList(
                    sections: _sectionsFor(visible),
                    values: _values,
                    texts: _texts,
                    color: widget.color,
                    bypass: widget.bypass,
                    allGroups: allGroups,
                    compact: widget.compact,
                    onChanged:
                        (param, value) =>
                            setState(() => _queue(param.index, value)),
                    onChangeEnd: _commit,
                    onReset: _reset,
                  ),
        ),
      ],
    );
  }
}

class _ParameterPage {
  const _ParameterPage({required this.key, required this.params});

  final String key;
  final List<FxParam> params;
}

class _ParameterSection {
  const _ParameterSection({required this.key, required this.params});

  final String key;
  final List<FxParam> params;
}

class _PageTabs extends StatelessWidget {
  const _PageTabs({
    required this.pages,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final List<_ParameterPage> pages;
  final String selected;
  final String Function(String page) labelFor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        itemCount: pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final page = pages[index];
          final active = page.key == selected;
          return InkWell(
            onTap: () => onSelected(page.key),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Text(
                labelFor(page.key),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.text : AppColors.textDim,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ParameterList extends StatelessWidget {
  const _ParameterList({
    required this.sections,
    required this.values,
    required this.texts,
    required this.color,
    required this.bypass,
    required this.allGroups,
    required this.compact,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  final List<_ParameterSection> sections;
  final Map<int, double> values;
  final Map<int, String> texts;
  final Color color;
  final bool bypass;
  final bool allGroups;
  final bool compact;
  final void Function(FxParam param, double value) onChanged;
  final void Function(int index, double value) onChangeEnd;
  final ValueChanged<FxParam> onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final multiGroup = sections.length > 1;
    final children = <Widget>[];
    for (final section in sections) {
      if (multiGroup) {
        children.add(
          _SectionLabel(
            label: parameterGroupLabel(l10n, section.key, allGroups: allGroups),
            count: section.params.length,
          ),
        );
      }
      for (final param in section.params) {
        final value =
            (values[param.index] ?? param.value).clamp(0.0, 1.0).toDouble();
        final text = texts[param.index] ?? param.text;
        children.add(
          _ParamCard(
            param: param,
            value: value,
            text: text,
            color: color,
            bypass: bypass,
            onChanged: (next) => onChanged(param, next),
            onChangeEnd: (next) => onChangeEnd(param.index, next),
            onReset: () => onReset(param),
          ),
        );
      }
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 16, 2, compact ? 14 : 16, 24),
      itemCount: children.length,
      separatorBuilder: (context, index) {
        final isHeader = index < 0 ? false : children[index] is _SectionLabel;
        return SizedBox(height: isHeader ? 2 : 6);
      },
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: AppColors.textFaint,
            ),
          ),
          const Spacer(),
          CountBadge('$count'),
        ],
      ),
    );
  }
}

class _ParamCard extends StatelessWidget {
  const _ParamCard({
    required this.param,
    required this.value,
    required this.text,
    required this.color,
    required this.bypass,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  final FxParam param;
  final double value;
  final String text;
  final Color color;
  final bool bypass;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final displayText = text.isNotEmpty ? text : '${(value * 100).round()}%';
    final toggled = value >= 0.5;
    final card = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child:
          param.isBoolean
              ? Row(
                children: [
                  Expanded(
                    child: _ParamLabel(
                      name: param.name,
                      text: toggled ? l10n.t('on') : l10n.t('off'),
                      color: color,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.t('reset'),
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 17),
                    visualDensity: VisualDensity.compact,
                    color: AppColors.textFaint,
                  ),
                  Switch(
                    value: toggled,
                    onChanged: (on) {
                      onChanged(on ? 1 : 0);
                      onChangeEnd(on ? 1 : 0);
                    },
                  ),
                ],
              )
              : param.isChoice && param.steps > 1
              ? _ChoiceControl(
                param: param,
                value: value,
                color: color,
                text: displayText,
                onSelected: (index) {
                  final next = param.valueForChoice(index);
                  onChanged(next);
                  onChangeEnd(next);
                },
                onReset: onReset,
              )
              : Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ParamLabel(
                          name: param.name,
                          text: displayText,
                          color: color,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.t('reset'),
                        onPressed: onReset,
                        icon: const Icon(Icons.restart_alt_rounded, size: 17),
                        visualDensity: VisualDensity.compact,
                        color: AppColors.textFaint,
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
                      divisions:
                          param.isInteger &&
                                  param.steps > 1 &&
                                  param.steps <= 32
                              ? math.min(param.steps - 1, 32)
                              : null,
                      onChanged: onChanged,
                      onChangeEnd: onChangeEnd,
                    ),
                  ),
                ],
              ),
    );
    return Opacity(opacity: bypass ? 0.62 : 1, child: card);
  }
}

class _ParamLabel extends StatelessWidget {
  const _ParamLabel({
    required this.name,
    required this.text,
    required this.color,
  });

  final String name;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
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
          constraints: const BoxConstraints(maxWidth: 148),
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
    );
  }
}

class _ChoiceControl extends StatelessWidget {
  const _ChoiceControl({
    required this.param,
    required this.value,
    required this.color,
    required this.text,
    required this.onSelected,
    required this.onReset,
  });

  final FxParam param;
  final double value;
  final Color color;
  final String text;
  final ValueChanged<int> onSelected;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels =
        param.choices.isNotEmpty
            ? param.choices
            : List<String>.generate(param.steps, (index) => '${index + 1}');
    final selected =
        param.steps > 1
            ? (value * (param.steps - 1)).round().clamp(0, labels.length - 1)
            : 0;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                param.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selected,
                isDense: true,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                dropdownColor: AppColors.panelHigh,
                style: const TextStyle(fontSize: 11, color: AppColors.text),
                icon: const Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: AppColors.textDim,
                ),
                items: [
                  for (var index = 0; index < labels.length; index++)
                    DropdownMenuItem(
                      value: index,
                      child: Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (index) {
                  if (index != null) onSelected(index);
                },
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.t('reset'),
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt_rounded, size: 17),
          visualDensity: VisualDensity.compact,
          color: AppColors.textFaint,
        ),
      ],
    );
  }
}

class _PresetBar extends StatelessWidget {
  const _PresetBar({
    required this.programs,
    required this.current,
    required this.busy,
    required this.onBrowse,
  });

  final List<FxProgram> programs;
  final int current;
  final bool busy;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final index = current.clamp(0, programs.length - 1);
    final active = programs[index];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 16,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('currentPreset'),
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: AppColors.textFaint,
                  ),
                ),
                Text(
                  active.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            )
          else
            OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(l10n.t('browsePresets')),
            ),
        ],
      ),
    );
  }
}

class _PresetPickerSheet extends StatefulWidget {
  const _PresetPickerSheet({required this.programs, required this.current});

  final List<FxProgram> programs;
  final int current;

  @override
  State<_PresetPickerSheet> createState() => _PresetPickerSheetState();
}

class _PresetPickerSheetState extends State<_PresetPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needle = _query.trim().toLowerCase();
    final filtered =
        needle.isEmpty
            ? widget.programs
            : widget.programs
                .where((program) => program.name.toLowerCase().contains(needle))
                .toList(growable: false);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.72, 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.t('presetSection'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.t('close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: InputDecoration(
                    hintText: l10n.t('searchPresets'),
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
                    filtered.isEmpty
                        ? Center(
                          child: Text(
                            l10n.t('noPresets'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                        )
                        : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final program = filtered[index];
                            final active = program.index == widget.current;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Material(
                                color:
                                    active
                                        ? AppColors.accentSoft
                                        : AppColors.surface,
                                borderRadius: BorderRadius.circular(9),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(9),
                                  onTap:
                                      () => Navigator.of(
                                        context,
                                      ).pop(program.index),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            program.shortName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight:
                                                  active
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                              color: AppColors.text,
                                            ),
                                          ),
                                        ),
                                        if (active)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 17,
                                            color: AppColors.accent,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
