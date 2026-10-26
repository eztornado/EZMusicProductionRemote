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

Future<void> showSettingsSheet(
  BuildContext context, {
  required RemoteController controller,
  required AppLanguage language,
  required ValueChanged<AppLanguage> onLanguageChanged,
}) {
  return showAppSheet<void>(
    context,
    maxWidth: 640,
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<AppSettings>(
      valueListenable: widget.controller.preferences,
      builder: (context, settings, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
          children: [
            SheetHeader(
              title: l10n.t('settingsTitle'),
              subtitle: l10n.t('workspaceSettings'),
              icon: Icons.settings_rounded,
            ),
            _SettingsCard(
              title: l10n.t('connectionSection'),
              icon: Icons.lan_outlined,
              children: [
                TextField(
                  controller: _clientName,
                  focusNode: _clientFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveClientName(),
                  decoration: InputDecoration(
                    labelText: l10n.t('clientName'),
                    helperText: l10n.t('clientNameHint'),
                    prefixIcon: const Icon(
                      Icons.phone_android_rounded,
                      size: 18,
                    ),
                    suffixIcon: IconButton(
                      tooltip: l10n.t('done'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      onPressed: () {
                        _saveClientName();
                        _clientFocus.unfocus();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SwitchRow(
                  title: l10n.t('autoReconnect'),
                  subtitle: l10n.t('autoReconnectHint'),
                  value: settings.autoReconnect,
                  onChanged:
                      (value) => widget.controller.setAutoReconnect(value),
                ),
                const Divider(height: 24),
                _ConnectionDetails(controller: widget.controller),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              title: l10n.t('languageSection'),
              icon: Icons.translate_rounded,
              children: [
                for (final language in AppLanguage.values)
                  _LanguageTile(
                    language: language,
                    selected: settings.language == language,
                    onTap: () {
                      widget.onLanguageChanged(language);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
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
                        onPressed: _disconnect,
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
                        onPressed: _forget,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 17,
                        ),
                        label: Text(l10n.t('forgetPairing')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
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
            ),
          ],
        );
      },
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

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
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
    final subtitle =
        language == AppLanguage.system
            ? l10n.t('systemDefault')
            : languageCode(language);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.panelAlt,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                languageCode(language).toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDim,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.text : AppColors.textDim,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: AppColors.accent,
              )
            else
              Icon(
                Icons.circle_outlined,
                size: 18,
                color: AppColors.borderStrong.withValues(alpha: 0.8),
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
