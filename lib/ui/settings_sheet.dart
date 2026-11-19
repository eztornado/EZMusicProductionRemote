import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/format.dart';
import '../data/settings_store.dart';
import '../l10n/strings.dart';
import '../models/project.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

enum _SettingsSection { connection, interface, security, about }

Future<void> showSettingsSheet(
  BuildContext context, {
  required RemoteController controller,
  required AppLanguage language,
  required ValueChanged<AppLanguage> onLanguageChanged,
}) {
  return showAppSheet<void>(
    context,
    maxWidth: 760,
    heightFactor: 0.92,
    builder:
        (ctx) => _SettingsSheet(
          controller: controller,
          initialLanguage: language,
          onLanguageChanged: onLanguageChanged,
        ),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.controller,
    required this.initialLanguage,
    required this.onLanguageChanged,
  });

  final RemoteController controller;
  final AppLanguage initialLanguage;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _clientName = TextEditingController(
    text: widget.controller.settings.clientName,
  );
  late final FocusNode _clientFocus = FocusNode();
  _SettingsSection _section = _SettingsSection.connection;

  @override
  void initState() {
    super.initState();
    _clientFocus.addListener(() {
      if (!_clientFocus.hasFocus) _saveClientName();
    });
  }

  @override
  void dispose() {
    _saveClientName();
    _clientName.dispose();
    _clientFocus.dispose();
    super.dispose();
  }

  void _saveClientName() {
    final value = _clientName.text.trim();
    if (value.isNotEmpty && value != widget.controller.settings.clientName) {
      widget.controller.setClientName(value);
    }
  }

  Future<void> _disconnect() async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('disconnect'),
      message: l10n.t('disconnectConfirm'),
      confirmLabel: l10n.t('disconnect'),
      danger: true,
      icon: Icons.link_off_rounded,
    );
    if (!ok || !mounted) return;
    await widget.controller.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _forget() async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('forgetPairing'),
      message: l10n.t('forgetPairingConfirm'),
      confirmLabel: l10n.t('forgetPairing'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await widget.controller.disconnect(forget: true);
    if (mounted) Navigator.of(context).pop();
  }

  String _sectionLabel(L10n l10n, _SettingsSection section) =>
      switch (section) {
        _SettingsSection.connection => l10n.t('connectionSection'),
        _SettingsSection.interface => l10n.t('interfaceSection'),
        _SettingsSection.security => l10n.t('securitySection'),
        _SettingsSection.about => l10n.t('aboutSection'),
      };

  IconData _sectionIcon(_SettingsSection section) => switch (section) {
    _SettingsSection.connection => Icons.lan_outlined,
    _SettingsSection.interface => Icons.palette_outlined,
    _SettingsSection.security => Icons.shield_outlined,
    _SettingsSection.about => Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<AppSettings>(
      valueListenable: widget.controller.preferences,
      builder: (context, settings, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: l10n.t('settingsTitle'),
              subtitle: l10n.t('workspaceSettings'),
              icon: Icons.settings_rounded,
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 600;
                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionChips(
                          selected: _section,
                          labelFor: (section) => _sectionLabel(l10n, section),
                          iconFor: _sectionIcon,
                          onSelected:
                              (section) => setState(() => _section = section),
                        ),
                        const Divider(height: 1),
                        Expanded(child: _panel(settings, wide: false)),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 196,
                        child: _SectionRail(
                          selected: _section,
                          labelFor: (section) => _sectionLabel(l10n, section),
                          iconFor: _sectionIcon,
                          onSelected:
                              (section) => setState(() => _section = section),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _panel(settings, wide: true)),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _panel(AppSettings settings, {required bool wide}) {
    final content = switch (_section) {
      _SettingsSection.connection => _ConnectionPanel(
        controller: widget.controller,
        settings: settings,
        clientName: _clientName,
        clientFocus: _clientFocus,
        onSaveClientName: _saveClientName,
      ),
      _SettingsSection.interface => _InterfacePanel(
        settings: settings,
        onLanguageChanged: widget.onLanguageChanged,
      ),
      _SettingsSection.security => _SecurityPanel(
        onDisconnect: _disconnect,
        onForget: _forget,
      ),
      _SettingsSection.about => _AboutPanel(),
    };
    return ListView(
      key: PageStorageKey<String>('settings-${_section.name}'),
      padding: EdgeInsets.fromLTRB(wide ? 20 : 16, 14, wide ? 20 : 16, 26),
      children: [content],
    );
  }
}

class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.onSelected,
  });

  final _SettingsSection selected;
  final String Function(_SettingsSection section) labelFor;
  final IconData Function(_SettingsSection section) iconFor;
  final ValueChanged<_SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
      children: [
        for (final section in _SettingsSection.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(section),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        section == selected
                            ? AppColors.accentSoft
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          section == selected
                              ? AppColors.accent.withValues(alpha: 0.55)
                              : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        iconFor(section),
                        size: 16,
                        color:
                            section == selected
                                ? AppColors.accent
                                : AppColors.textFaint,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          labelFor(section),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                section == selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                            color:
                                section == selected
                                    ? AppColors.text
                                    : AppColors.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.selected,
    required this.labelFor,
    required this.iconFor,
    required this.onSelected,
  });

  final _SettingsSection selected;
  final String Function(_SettingsSection section) labelFor;
  final IconData Function(_SettingsSection section) iconFor;
  final ValueChanged<_SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        itemCount: _SettingsSection.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final section = _SettingsSection.values[index];
          final active = section == selected;
          return InkWell(
            onTap: () => onSelected(section),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      active
                          ? AppColors.accent.withValues(alpha: 0.75)
                          : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    iconFor(section),
                    size: 14,
                    color: active ? AppColors.accent : AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    labelFor(section),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? AppColors.text : AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.controller,
    required this.settings,
    required this.clientName,
    required this.clientFocus,
    required this.onSaveClientName,
  });

  final RemoteController controller;
  final AppSettings settings;
  final TextEditingController clientName;
  final FocusNode clientFocus;
  final VoidCallback onSaveClientName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          title: l10n.t('connectionSection'),
          icon: Icons.lan_outlined,
          children: [
            TextField(
              controller: clientName,
              focusNode: clientFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSaveClientName(),
              decoration: InputDecoration(
                labelText: l10n.t('clientName'),
                helperText: l10n.t('clientNameHint'),
                prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                suffixIcon: IconButton(
                  tooltip: l10n.t('done'),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  onPressed: () {
                    onSaveClientName();
                    clientFocus.unfocus();
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SwitchRow(
              title: l10n.t('autoReconnect'),
              subtitle: l10n.t('autoReconnectHint'),
              value: settings.autoReconnect,
              onChanged: (value) => controller.setAutoReconnect(value),
            ),
            const Divider(height: 24),
            _ConnectionDetails(controller: controller),
          ],
        ),
      ],
    );
  }
}

class _InterfacePanel extends StatelessWidget {
  const _InterfacePanel({
    required this.settings,
    required this.onLanguageChanged,
  });

  final AppSettings settings;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          title: l10n.t('languageSection'),
          icon: Icons.translate_rounded,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final language in AppLanguage.values)
                  _LanguageChip(
                    language: language,
                    selected: settings.language == language,
                    onTap: () => onLanguageChanged(language),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l10n.t('interfaceBody'),
              style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                color: AppColors.textFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          title: l10n.t('interfaceSection'),
          icon: Icons.palette_outlined,
          children: [
            Text(
              l10n.t('interfaceStudioNote'),
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textDim,
              ),
            ),
            const SizedBox(height: 12),
            StatusPill(
              label: l10n.t('studio'),
              color: AppColors.accent,
              icon: Icons.computer_rounded,
              dense: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.onDisconnect, required this.onForget});

  final VoidCallback onDisconnect;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.t('securitySection'),
      icon: Icons.shield_outlined,
      children: [
        Text(
          l10n.t('securityBody'),
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 10),
        StatusPill(
          label: l10n.t('securityWarning'),
          color: AppColors.warning,
          icon: Icons.lan_outlined,
          dense: true,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off_rounded, size: 17),
                label: Text(l10n.t('disconnect')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(
                    color: AppColors.danger.withValues(alpha: 0.5),
                  ),
                ),
                onPressed: onForget,
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                label: Text(l10n.t('forgetPairing')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.t('aboutSection'),
      icon: Icons.info_outline_rounded,
      children: [
        Row(
          children: [
            const BrandMark(size: 46),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.t('appName'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                Text(
                  l10n.t('appVersion', {'version': kAppVersion}),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('aboutBody'),
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: AppColors.textDim,
          ),
        ),
        const Divider(height: 24),
        InfoRow(
          label: l10n.t('protocolVersion', {'version': ''}).trim(),
          value: '$kRemoteProtocolVersion',
          icon: Icons.api_rounded,
        ),
        InfoRow(
          label: l10n.t('madeBy'),
          value: 'EZMusicProduction',
          icon: Icons.favorite_outline_rounded,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              () => showLicensePage(
                context: context,
                applicationName: l10n.t('appName'),
                applicationVersion: kAppVersion,
              ),
          icon: const Icon(Icons.description_outlined, size: 17),
          label: Text(l10n.t('licences')),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textFaint),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch (language) {
      AppLanguage.system => l10n.t('languageSystem'),
      AppLanguage.english => l10n.t('english'),
      AppLanguage.spanish => l10n.t('spanish'),
      AppLanguage.japanese => l10n.t('japanese'),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.black),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : AppColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteConnection>(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        return ValueListenableBuilder<RemoteProject?>(
          valueListenable: controller.project,
          builder: (context, project, _) {
            return ValueListenableBuilder<ServerInfo?>(
              valueListenable: controller.server,
              builder: (context, server, _) {
                if (!connection.isConnected) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoRow(
                        label: l10n.t('state'),
                        value: l10n.t('offline'),
                        icon: Icons.cloud_off_rounded,
                        valueColor: AppColors.textDim,
                      ),
                      if (connection.host != null)
                        InfoRow(
                          label: l10n.t('serverAddress'),
                          value: '${connection.host}:${connection.port}',
                          icon: Icons.dns_outlined,
                        ),
                      if (connection.host != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => controller.reconnectNow(),
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: Text(l10n.t('reconnect')),
                          ),
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(
                      label: l10n.t('state'),
                      value: l10n.t('online'),
                      icon: Icons.cloud_done_outlined,
                      valueColor: AppColors.success,
                    ),
                    InfoRow(
                      label: l10n.t('serverAddress'),
                      value: '${connection.host}:${connection.port}',
                      icon: Icons.dns_outlined,
                    ),
                    InfoRow(
                      label: l10n.t('project'),
                      value: project?.name ?? l10n.t('unknownProject'),
                      icon: Icons.folder_outlined,
                    ),
                    if (project != null)
                      InfoRow(
                        label: l10n.t('revision', {'revision': ''}).trim(),
                        value: '${project.revision}',
                        icon: Icons.history_rounded,
                      ),
                    if (project != null)
                      InfoRow(
                        label: l10n.t('projectDuration'),
                        value: formatClock(project.duration, showMillis: false),
                        icon: Icons.timelapse_rounded,
                      ),
                    if (server != null) ...[
                      InfoRow(
                        label: l10n.t('serverVersion', {'version': ''}).trim(),
                        value: '${server.protocol}',
                        icon: Icons.api_rounded,
                      ),
                      InfoRow(
                        label: l10n.t('clientId'),
                        value: '${server.clientId}',
                        icon: Icons.badge_outlined,
                      ),
                      if (server.capabilities.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: [
                              for (final capability in server.capabilities)
                                CountBadge(capability),
                            ],
                          ),
                        ),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
