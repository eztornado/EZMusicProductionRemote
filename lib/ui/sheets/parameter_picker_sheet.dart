import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/project.dart';
import '../../models/session.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// One automatable plugin parameter, returned by [showParameterPicker].
class ParameterChoice {
  const ParameterChoice({
    required this.slotKind,
    required this.slotIndex,
    required this.paramIndex,
    required this.name,
    required this.value,
  });

  final int slotKind;
  final int slotIndex;
  final int paramIndex;
  final String name;
  final double value;
}

Future<ParameterChoice?> showParameterPicker(
  BuildContext context, {
  required RemoteController controller,
  required RemoteTrack track,
}) {
  return showAppSheet<ParameterChoice>(
    context,
    maxWidth: 560,
    heightFactor: 0.88,
    builder: (ctx) => _ParameterPicker(controller: controller, track: track),
  );
}

class _ParameterPicker extends StatefulWidget {
  const _ParameterPicker({required this.controller, required this.track});

  final RemoteController controller;
  final RemoteTrack track;

  @override
  State<_ParameterPicker> createState() => _ParameterPickerState();
}

class _ParameterPickerState extends State<_ParameterPicker> {
  final TextEditingController _search = TextEditingController();
  List<_SlotGroup> _groups = const <_SlotGroup>[];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
    final refs = <_SlotRef>[];
    if (widget.track.isInstrument && widget.track.hasInstrument) {
      refs.add(
        _SlotRef(
          kind: 1,
          index: 0,
          name: widget.track.instrument,
          isInstrument: true,
        ),
      );
    }
    for (final slot in widget.track.fx) {
      refs.add(_SlotRef(kind: 0, index: slot.index, name: slot.name));
    }
    final groups = <_SlotGroup>[];
    for (final ref in refs) {
      try {
        final params = await widget.controller.fetchFxParams(
          trackId: widget.track.id,
          slotKind: ref.kind,
          slotIndex: ref.index,
        );
        if (params.isNotEmpty) {
          groups.add(_SlotGroup(ref: ref, params: params));
        }
      } on Object {
        // A broken plugin should not block the rest of the chain.
      }
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  List<_SlotGroup> get _filtered {
    if (_query.isEmpty) return _groups;
    final needle = _query.toLowerCase();
    final result = <_SlotGroup>[];
    for (final group in _groups) {
      final params = group.params
          .where((param) => param.name.toLowerCase().contains(needle))
          .toList(growable: false);
      if (params.isNotEmpty) {
        result.add(_SlotGroup(ref: group.ref, params: params));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filtered = _filtered;
    return Column(
      children: [
        SheetHeader(
          title: l10n.t('chooseParameter'),
          subtitle: widget.track.name,
          icon: Icons.multiline_chart_rounded,
          trailing: IconButton(
            tooltip: l10n.t('retry'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
        ),
        if (!_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: l10n.t('searchParameters'),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
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
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.t('loading'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textDim,
                          ),
                        ),
                      ],
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
                  : filtered.isEmpty
                  ? EmptyState(
                    icon: Icons.tune_rounded,
                    title: l10n.t('noParameters'),
                    message: l10n.t('noPluginSelected'),
                    compact: true,
                  )
                  : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                    children: [
                      for (final group in filtered) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                          child: Row(
                            children: [
                              Icon(
                                group.ref.isInstrument
                                    ? Icons.piano_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 13,
                                color:
                                    group.ref.isInstrument
                                        ? AppColors.accent
                                        : AppColors.textFaint,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  group.ref.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.6,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ),
                              CountBadge('${group.params.length}'),
                            ],
                          ),
                        ),
                        for (final param in group.params)
                          _ParameterRow(
                            group: group.ref,
                            param: param,
                            onTap:
                                () => Navigator.of(context).pop(
                                  ParameterChoice(
                                    slotKind: group.ref.kind,
                                    slotIndex: group.ref.index,
                                    paramIndex: param.index,
                                    name: param.name,
                                    value: param.value,
                                  ),
                                ),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
        ),
      ],
    );
  }
}

class _SlotRef {
  const _SlotRef({
    required this.kind,
    required this.index,
    required this.name,
    this.isInstrument = false,
  });

  final int kind;
  final int index;
  final String name;
  final bool isInstrument;
}

class _SlotGroup {
  const _SlotGroup({required this.ref, required this.params});

  final _SlotRef ref;
  final List<FxParam> params;
}

class _ParameterRow extends StatelessWidget {
  const _ParameterRow({
    required this.group,
    required this.param,
    required this.onTap,
  });

  final _SlotRef group;
  final FxParam param;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  param.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  param.text.isEmpty
                      ? '${(param.value * 100).round()}%'
                      : param.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.add_chart_rounded,
                size: 16,
                color:
                    group.isInstrument ? AppColors.accent : AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
