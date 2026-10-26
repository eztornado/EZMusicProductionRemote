import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/session.dart';
import '../../state/remote_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Shared plugin browser used by the insert-chain and master-FX editors.
Future<PluginInfo?> showPluginPicker(
  BuildContext context,
  RemoteController controller, {
  bool instruments = false,
  String? title,
}) {
  return showAppSheet<PluginInfo>(
    context,
    maxWidth: 560,
    heightFactor: 0.88,
    builder:
        (ctx) => _PluginPicker(
          controller: controller,
          instruments: instruments,
          title: title,
        ),
  );
}

class _PluginPicker extends StatefulWidget {
  const _PluginPicker({
    required this.controller,
    required this.instruments,
    this.title,
  });

  final RemoteController controller;
  final bool instruments;
  final String? title;

  @override
  State<_PluginPicker> createState() => _PluginPickerState();
}

class _PluginPickerState extends State<_PluginPicker> {
  final TextEditingController _search = TextEditingController();
  Future<List<PluginInfo>?>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load(force: false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<PluginInfo>?> _load({required bool force}) {
    return widget.controller.loadPlugins(force: force);
  }

  void _reload() {
    setState(() {
      _future = _load(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        SheetHeader(
          title: widget.title ?? l10n.t('choosePlugin'),
          subtitle: l10n.t(
            widget.instruments ? 'instrumentsTab' : 'effectsTab',
          ),
          icon:
              widget.instruments
                  ? Icons.piano_rounded
                  : Icons.auto_awesome_rounded,
          trailing: IconButton(
            tooltip: l10n.t('reloadPlugins'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              hintText: l10n.t('pluginSearchHint'),
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
          child: FutureBuilder<List<PluginInfo>?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
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
                        l10n.t('loadingPlugins'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: l10n.t('error'),
                  message: l10n.t('errorCommandFailed', {
                    'error': '${snapshot.error}',
                  }),
                  action: OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(l10n.t('retry')),
                  ),
                );
              }
              final all = snapshot.data ?? const <PluginInfo>[];
              final filtered = all
                  .where((plugin) => plugin.isInstrument == widget.instruments)
                  .where((plugin) {
                    if (_query.isEmpty) return true;
                    final needle = _query.toLowerCase();
                    return plugin.name.toLowerCase().contains(needle) ||
                        plugin.format.toLowerCase().contains(needle);
                  })
                  .toList(growable: false);
              if (filtered.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off_rounded,
                  title: l10n.t('pluginListEmpty'),
                  message: l10n.t('pluginSearchHint'),
                  compact: true,
                  action: OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(l10n.t('reloadPlugins')),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final plugin = filtered[index];
                  return _PluginRow(
                    plugin: plugin,
                    onTap: () => Navigator.of(context).pop(plugin),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({required this.plugin, required this.onTap});

  final PluginInfo plugin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.panelAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  plugin.isInstrument
                      ? Icons.piano_rounded
                      : Icons.auto_awesome_rounded,
                  size: 17,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plugin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plugin.format.isEmpty
                          ? l10n.t('pluginFormat')
                          : plugin.format,
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
