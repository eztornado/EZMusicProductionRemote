import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/transport_bar.dart';
import 'automation_screen.dart';
import 'fx_screen.dart';
import 'mixer_screen.dart';
import 'settings_sheet.dart';
import 'timeline_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
  });

  final RemoteController controller;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int _index = 0;

  RemoteController get _controller => widget.controller;

  void _openFx([int? trackId]) {
    if (trackId != null) _controller.selectTrack(trackId);
    setState(() => _index = 2);
  }

  void _openAutomation([int? trackId]) {
    if (trackId != null) _controller.selectTrack(trackId, clearClip: false);
    setState(() => _index = 3);
  }

  void _openSettings() {
    showSettingsSheet(
      context,
      controller: _controller,
      language: widget.language,
      onLanguageChanged: widget.onLanguageChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 820;
        return Scaffold(
          appBar: _WorkspaceAppBar(
            controller: _controller,
            onSettings: _openSettings,
            compact: constraints.maxWidth < 600,
          ),
          bottomNavigationBar:
              useRail
                  ? null
                  : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected:
                        (index) => setState(() => _index = index),
                    destinations: [
                      NavigationDestination(
                        icon: const Icon(Icons.view_timeline_outlined),
                        selectedIcon: const Icon(Icons.view_timeline_rounded),
                        label: l10n.t('navigationTimeline'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.equalizer_outlined),
                        selectedIcon: const Icon(Icons.equalizer_rounded),
                        label: l10n.t('navigationMixer'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.tune_outlined),
                        selectedIcon: const Icon(Icons.tune_rounded),
                        label: l10n.t('navigationEffects'),
                      ),
                      NavigationDestination(
                        icon: const Icon(Icons.show_chart_rounded),
                        selectedIcon: const Icon(Icons.multiline_chart_rounded),
                        label: l10n.t('navigationAutomation'),
                      ),
                    ],
                  ),
          body: Column(
            children: [
              TransportBar(controller: _controller),
              _RecoveryBanner(
                controller: _controller,
                onSettings: _openSettings,
              ),
              Expanded(
                child: Row(
                  children: [
                    if (useRail)
                      _Rail(
                        index: _index,
                        onChanged: (index) => setState(() => _index = index),
                        extended: constraints.maxWidth >= 1180,
                      ),
                    if (useRail)
                      const VerticalDivider(width: 1, color: AppColors.border),
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: [
                          TickerMode(
                            enabled: _index == 0,
                            child: TimelineScreen(
                              controller: _controller,
                              active: _index == 0,
                              onOpenFx: _openFx,
                              onOpenAutomation: _openAutomation,
                            ),
                          ),
                          TickerMode(
                            enabled: _index == 1,
                            child: MixerScreen(
                              controller: _controller,
                              onOpenFx: _openFx,
                              onOpenAutomation: _openAutomation,
                            ),
                          ),
                          TickerMode(
                            enabled: _index == 2,
                            child: FxScreen(controller: _controller),
                          ),
                          TickerMode(
                            enabled: _index == 3,
                            child: AutomationScreen(controller: _controller),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _WorkspaceAppBar({
    required this.controller,
    required this.onSettings,
    required this.compact,
  });

  final RemoteController controller;
  final VoidCallback onSettings;
  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteConnection>(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        return ValueListenableBuilder<RemoteProject?>(
          valueListenable: controller.project,
          builder: (context, project, _) {
            final connected = connection.isConnected;
            return AppBar(
              toolbarHeight: 56,
              titleSpacing: 12,
              backgroundColor: AppColors.backgroundElevated,
              shape: const Border(bottom: BorderSide(color: AppColors.border)),
              title: Row(
                children: [
                  const BrandMark(size: 34, tile: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          project?.name ?? l10n.t('projectFallback'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          connected
                              ? '${connection.host}:${connection.port}'
                                  '${compact || project == null ? '' : '  ·  ${l10n.t('revision', {'revision': project.revision})}'}'
                              : l10n.t('readOnlyBanner'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: AppColors.textFaint,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                _ConnectionChip(
                  connected: connected,
                  phase: connection.phase,
                  onTap: onSettings,
                ),
                const SizedBox(width: 6),
                if (!compact) ...[
                  AppIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: l10n.t('undo'),
                    minSize: 36,
                    size: 18,
                    onPressed:
                        connected && (project?.canUndo ?? false)
                            ? () => controller.undo()
                            : null,
                  ),
                  AppIconButton(
                    icon: Icons.redo_rounded,
                    tooltip: l10n.t('redo'),
                    minSize: 36,
                    size: 18,
                    onPressed:
                        connected && (project?.canRedo ?? false)
                            ? () => controller.redo()
                            : null,
                  ),
                  const SizedBox(width: 2),
                ],
                AppIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: l10n.t('settings'),
                  minSize: 38,
                  onPressed: onSettings,
                ),
                const SizedBox(width: 4),
              ],
            );
          },
        );
      },
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.connected,
    required this.phase,
    required this.onTap,
  });

  final bool connected;
  final ConnectionPhase phase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reconnecting = phase == ConnectionPhase.reconnecting;
    final color =
        connected
            ? AppColors.success
            : reconnecting
            ? AppColors.warning
            : AppColors.danger;
    final label =
        connected
            ? l10n.t('online')
            : reconnecting
            ? l10n.t('reconnecting')
            : l10n.t('offline');
    return Tooltip(
      message: l10n.t('workspaceSettings'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: StatusPill(label: label, color: color, dense: true),
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.onChanged,
    required this.extended,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (
        Icons.view_timeline_outlined,
        Icons.view_timeline_rounded,
        l10n.t('navigationTimeline'),
      ),
      (
        Icons.equalizer_outlined,
        Icons.equalizer_rounded,
        l10n.t('navigationMixer'),
      ),
      (Icons.tune_outlined, Icons.tune_rounded, l10n.t('navigationEffects')),
      (
        Icons.show_chart_rounded,
        Icons.multiline_chart_rounded,
        l10n.t('navigationAutomation'),
      ),
    ];
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onChanged,
      extended: extended,
      minWidth: 74,
      groupAlignment: -0.55,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      destinations: [
        for (final destination in destinations)
          NavigationRailDestination(
            icon: Icon(destination.$1),
            selectedIcon: Icon(destination.$2),
            label: Text(destination.$3),
          ),
      ],
    );
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.controller, required this.onSettings});

  final RemoteController controller;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConnection>(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        if (connection.isConnected) return const SizedBox.shrink();
        final l10n = context.l10n;
        final reconnecting = connection.phase == ConnectionPhase.reconnecting;
        final color = reconnecting ? AppColors.warning : AppColors.danger;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.28)),
            ),
          ),
          child: Row(
            children: [
              if (reconnecting)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: color,
                  ),
                )
              else
                Icon(Icons.cloud_off_rounded, size: 17, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  reconnecting
                      ? '${l10n.t('reconnectingBanner')}'
                          '${connection.attempt > 1 ? '  ·  ${l10n.t('reconnectAttempt', {'attempt': connection.attempt})}' : ''}'
                      : l10n.t('connectionLost'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => controller.reconnectNow(),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  minimumSize: const Size(30, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(l10n.t('reconnectNow')),
              ),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                color: color,
                tooltip: l10n.t('settings'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );
      },
    );
  }
}
