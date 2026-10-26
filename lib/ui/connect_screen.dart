import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/network.dart';
import '../data/discovery_service.dart';
import '../data/settings_store.dart';
import '../l10n/strings.dart';
import '../models/session.dart';
import '../state/remote_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'settings_sheet.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.controller,
    required this.language,
    required this.onLanguageChanged,
  });

  final RemoteController controller;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '47823');
  final DiscoveryService _discovery = DiscoveryService();

  StreamSubscription<DiscoveredServer>? _scanSubscription;
  final List<DiscoveredServer> _servers = [];
  bool _scanning = false;
  String? _scanError;
  String? _manualError;
  String? _busyEndpoint;

  RemoteController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final last = _controller.settings.lastDevice;
    if (last != null) {
      _host.text = last.host;
      _port.text = last.port.toString();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scan();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  int get _portValue => int.tryParse(_port.text.trim()) ?? 47823;

  Future<void> _scan() async {
    if (_scanning) return;
    await _scanSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scanError = null;
      _servers.clear();
    });
    final subscription = _discovery
        .scan(portOverride: _portValue)
        .listen(
          (server) {
            if (!mounted) return;
            if (_servers.any((item) => item.id == server.id)) return;
            setState(() {
              _servers.add(server);
              _servers.sort((a, b) => a.host.compareTo(b.host));
            });
          },
          onError: (Object _) {
            if (!mounted) return;
            setState(() => _scanError = context.l10n.t('searchFailed'));
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _scanning = false);
          },
        );
    _scanSubscription = subscription;
  }

  RemoteDevice? _savedFor(String host, int port) {
    return _controller.settings.deviceFor(host.trim().toLowerCase(), port);
  }

  Future<void> _connect({
    required String host,
    required int port,
    String? name,
    String? token,
  }) async {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) {
      setState(() => _manualError = context.l10n.t('invalidHost'));
      return;
    }
    final saved = _savedFor(normalized, port);
    final effectiveToken = token ?? saved?.token;
    if (effectiveToken == null || effectiveToken.trim().isEmpty) {
      await _openPairing(
        host: normalized,
        port: port,
        name: name ?? saved?.projectName ?? normalized,
      );
      return;
    }

    setState(() {
      _manualError = null;
      _busyEndpoint = '$normalized:$port';
    });
    final ok = await _controller.pair(
      host: normalized,
      port: port,
      token: effectiveToken,
    );
    if (!mounted) return;
    setState(() => _busyEndpoint = null);
    if (ok) return;
    if (_controller.connection.value.phase == ConnectionPhase.authFailed) {
      await _openPairing(
        host: normalized,
        port: port,
        name: name ?? saved?.projectName ?? normalized,
        initialError: context.l10n.t('wrongCode'),
      );
    }
  }

  Future<void> _openPairing({
    required String host,
    required int port,
    required String name,
    String? initialError,
  }) async {
    final saved = _savedFor(host, port);
    final result = await showPairingSheet(
      context,
      controller: _controller,
      host: host,
      port: port,
      name: name,
      initialError: initialError,
      savedToken: saved?.token,
    );
    if (!mounted) return;
    if (result) {
      await _scanSubscription?.cancel();
      setState(() => _scanning = false);
    }
  }

  Future<void> _manualConnect() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _manualError = context.l10n.t('invalidHost'));
      return;
    }
    final endpoint = parseEndpointInput(_host.text, defaultPort: port);
    if (endpoint == null) {
      setState(() => _manualError = context.l10n.t('invalidHost'));
      return;
    }
    setState(() => _manualError = null);
    await _connect(
      host: endpoint.host,
      port: endpoint.port,
      name: endpoint.host,
    );
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
    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(onSettings: _openSettings),
                          const SizedBox(height: 26),
                          _StatusCard(
                            controller: _controller,
                            onPair:
                                (host, port, name) => _openPairing(
                                  host: host,
                                  port: port,
                                  name: name,
                                ),
                          ),
                          ValueListenableBuilder<AppSettings>(
                            valueListenable: _controller.preferences,
                            builder: (context, settings, _) {
                              if (settings.devices.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 22),
                                child: _RecentSection(
                                  devices: settings.devices,
                                  busyEndpoint: _busyEndpoint,
                                  onConnect:
                                      (device) => _connect(
                                        host: device.host,
                                        port: device.port,
                                        name: device.projectName,
                                        token: device.token,
                                      ),
                                  onForget: (device) => _forget(device),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 22),
                          _DiscoverySection(
                            scanning: _scanning,
                            servers: _servers,
                            error: _scanError,
                            busyEndpoint: _busyEndpoint,
                            onScan: _scan,
                            onSelect:
                                (server) => _connect(
                                  host: server.host,
                                  port: server.port,
                                  name: server.app,
                                ),
                          ),
                          const SizedBox(height: 22),
                          _ManualSection(
                            host: _host,
                            port: _port,
                            error: _manualError,
                            busy: _busyEndpoint != null,
                            onConnect: _manualConnect,
                          ),
                          const SizedBox(height: 20),
                          _Hints(),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _forget(RemoteDevice device) async {
    final l10n = context.l10n;
    final ok = await showConfirmDialog(
      context,
      title: l10n.t('forgetDevice'),
      message: l10n.t('forgetDeviceConfirm', {
        'name':
            device.projectName.isNotEmpty ? device.projectName : device.host,
      }),
      confirmLabel: l10n.t('forgetDevice'),
      danger: true,
      icon: Icons.link_off_rounded,
    );
    if (ok && mounted) await _controller.forgetDevice(device);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandMark(size: 54),
        const SizedBox(width: 14),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [ArtistName(), SizedBox(height: 5)],
            ),
          ),
        ),
        AppIconButton(
          icon: Icons.settings_outlined,
          tooltip: l10n.t('settings'),
          onPressed: onSettings,
          minSize: 42,
        ),
      ],
    ).let((row) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row,
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  l10n.t('connectSubtitle'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textDim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatusPill(
            label: l10n.t('securityWarning'),
            color: AppColors.warning,
            icon: Icons.lan_outlined,
            dense: true,
          ),
        ],
      );
    });
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller, required this.onPair});

  final RemoteController controller;
  final void Function(String host, int port, String name) onPair;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoteConnection>(
      valueListenable: controller.connection,
      builder: (context, connection, _) {
        if (connection.phase == ConnectionPhase.idle ||
            connection.phase == ConnectionPhase.connected ||
            connection.host == null) {
          return const SizedBox.shrink();
        }
        final l10n = context.l10n;
        final busy =
            connection.phase == ConnectionPhase.connecting ||
            connection.phase == ConnectionPhase.reconnecting;
        final failed = connection.phase == ConnectionPhase.error;
        final auth = connection.phase == ConnectionPhase.authFailed;
        final color =
            busy
                ? AppColors.accent
                : auth
                ? AppColors.warning
                : AppColors.danger;
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: panelDecoration(
              color: color.withValues(alpha: 0.07),
              borderColor: color.withValues(alpha: 0.28),
            ),
            child: Row(
              children: [
                if (busy)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: color,
                    ),
                  )
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      auth ? Icons.password_rounded : Icons.cloud_off_rounded,
                      size: 19,
                      color: color,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        busy
                            ? l10n.t('connectingTo', {'host': connection.host})
                            : auth
                            ? l10n.t('authFailed')
                            : l10n.t('connectionFailed'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        busy
                            ? '${connection.host}:${connection.port}'
                            : friendlyConnectionError(l10n, connection),
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                if (auth)
                  TextButton(
                    onPressed:
                        () => onPair(
                          connection.host!,
                          connection.port,
                          connection.host!,
                        ),
                    child: Text(l10n.t('enterCode')),
                  )
                else if (failed)
                  TextButton(
                    onPressed: () => controller.reconnectNow(),
                    child: Text(l10n.t('retry')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.devices,
    required this.busyEndpoint,
    required this.onConnect,
    required this.onForget,
  });

  final List<RemoteDevice> devices;
  final String? busyEndpoint;
  final void Function(RemoteDevice device) onConnect;
  final void Function(RemoteDevice device) onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.t('recentDevices')),
        for (final device in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentDeviceCard(
              device: device,
              busy: busyEndpoint == device.id,
              onTap: () => onConnect(device),
              onForget: () => onForget(device),
            ),
          ),
      ],
    );
  }
}

class _RecentDeviceCard extends StatelessWidget {
  const _RecentDeviceCard({
    required this.device,
    required this.busy,
    required this.onTap,
    required this.onForget,
  });

  final RemoteDevice device;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    busy
                        ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(
                          Icons.computer_rounded,
                          size: 20,
                          color: AppColors.accent,
                        ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.projectName.isEmpty
                          ? l10n.t('savedDevice')
                          : device.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.host}:${device.port}  ·  ${l10n.t('lastUsed', {'time': relativeTime(device.lastUsed, l10n)})}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (!busy)
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: AppColors.textFaint.withValues(alpha: 0.7),
                ),
              PopupMenuButton<String>(
                tooltip: l10n.t('more'),
                color: AppColors.panel,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: AppColors.textFaint,
                ),
                onSelected: (value) {
                  if (value == 'forget') onForget();
                },
                itemBuilder:
                    (context) => [
                      PopupMenuItem(
                        value: 'forget',
                        child: Row(
                          children: [
                            const Icon(Icons.link_off_rounded, size: 17),
                            const SizedBox(width: 10),
                            Text(l10n.t('forgetDevice')),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({
    required this.scanning,
    required this.servers,
    required this.error,
    required this.busyEndpoint,
    required this.onScan,
    required this.onSelect,
  });

  final bool scanning;
  final List<DiscoveredServer> servers;
  final String? error;
  final String? busyEndpoint;
  final VoidCallback onScan;
  final void Function(DiscoveredServer server) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.t('findStudio'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scanning ? l10n.t('scanning') : l10n.t('sameNetworkHint'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: scanning ? null : onScan,
                icon:
                    scanning
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.radar_rounded, size: 17),
                label: Text(l10n.t(scanning ? 'scanning' : 'scan')),
              ),
            ],
          ),
          if (scanning) ...[
            const SizedBox(height: 10),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ],
          if (servers.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final server in servers)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _ServerTile(
                  server: server,
                  busy: busyEndpoint == server.id,
                  onTap: () => onSelect(server),
                ),
              ),
          ] else if (!scanning) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wifi_find_rounded,
                    size: 19,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.t('noServersFound'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.busy,
    required this.onTap,
  });

  final DiscoveredServer server;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.speaker_rounded,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      server.app,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      '${server.host}:${server.port}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textFaint,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'WEB SOCKET',
                color: AppColors.success,
                dense: true,
              ),
              if (busy) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    ).withTooltip(l10n.t('tapToConnect'));
  }
}

class _ManualSection extends StatelessWidget {
  const _ManualSection({
    required this.host,
    required this.port,
    required this.error,
    required this.busy,
    required this.onConnect,
  });

  final TextEditingController host;
  final TextEditingController port;
  final String? error;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: panelDecoration(color: AppColors.backgroundElevated),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('manualConnection'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: host,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.t('address'),
                    hintText: l10n.t('hostHint'),
                    prefixIcon: const Icon(Icons.dns_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l10n.t('portLabel')),
                  onSubmitted: (_) => onConnect(),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy ? null : onConnect,
            icon:
                busy
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.login_rounded, size: 18),
            label: Text(l10n.t('connectAction')),
          ),
        ],
      ),
    );
  }
}

class _Hints extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HintLine(icon: Icons.wifi_rounded, text: l10n.t('sameNetworkHint')),
        const SizedBox(height: 7),
        _HintLine(
          icon: Icons.settings_remote_rounded,
          text: l10n.t('enableRemoteHint'),
        ),
      ],
    );
  }
}

class _HintLine extends StatelessWidget {
  const _HintLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppColors.textFaint,
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> showPairingSheet(
  BuildContext context, {
  required RemoteController controller,
  required String host,
  required int port,
  required String name,
  String? initialError,
  String? savedToken,
}) async {
  final result = await showAppSheet<bool>(
    context,
    maxWidth: 460,
    heightFactor: 0.8,
    builder:
        (ctx) => _PairingSheet(
          controller: controller,
          host: host,
          port: port,
          name: name,
          initialError: initialError,
          savedToken: savedToken,
        ),
  );
  return result ?? false;
}

class _PairingSheet extends StatefulWidget {
  const _PairingSheet({
    required this.controller,
    required this.host,
    required this.port,
    required this.name,
    this.initialError,
    this.savedToken,
  });

  final RemoteController controller;
  final String host;
  final int port;
  final String name;
  final String? initialError;
  final String? savedToken;

  @override
  State<_PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<_PairingSheet> {
  final TextEditingController _code = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? token]) async {
    final value = (token ?? _code.text).trim();
    if (value.length != 6 || int.tryParse(value) == null) {
      setState(() => _error = context.l10n.t('errorCodeLength'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.pair(
      host: widget.host,
      port: widget.port,
      token: value,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final connection = widget.controller.connection.value;
    setState(() {
      _busy = false;
      _error =
          connection.phase == ConnectionPhase.authFailed
              ? context.l10n.t('wrongCode')
              : friendlyConnectionError(context.l10n, connection);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      children: [
        SheetHeader(
          title: l10n.t('pairingTitle', {'name': widget.name}),
          icon: Icons.link_rounded,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                size: 17,
                color: AppColors.textFaint,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${widget.host}:${widget.port}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDim,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const StatusPill(
                label: 'WS',
                color: AppColors.success,
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.t('pairingSubtitle'),
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.textDim,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _code,
          focusNode: _focus,
          autofocus: false,
          maxLength: 6,
          obscureText: false,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: const TextStyle(
            fontSize: 26,
            letterSpacing: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: '••••••',
            hintStyle: const TextStyle(
              letterSpacing: 14,
              color: AppColors.textFaint,
            ),
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            prefixIcon: const SizedBox(width: 0),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 15,
                color: AppColors.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon:
              _busy
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.link_rounded, size: 19),
          label: Text(l10n.t('connectAction')),
        ),
        if (widget.savedToken != null && widget.savedToken!.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _submit(widget.savedToken),
            icon: const Icon(Icons.key_rounded, size: 17),
            label: Text(l10n.t('useSavedCode')),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          l10n.t('enableRemoteHint'),
          style: const TextStyle(
            fontSize: 10.5,
            height: 1.4,
            color: AppColors.textFaint,
          ),
        ),
      ],
    );
  }
}

extension on Widget {
  Widget withTooltip(String message) => Tooltip(message: message, child: this);
}

extension _Let<T> on T {
  R let<R>(R Function(T value) block) => block(this);
}
