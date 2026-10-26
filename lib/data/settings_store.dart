import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/json.dart';
import '../l10n/strings.dart';
import '../models/session.dart';

class AppSettings {
  const AppSettings({
    this.language = AppLanguage.system,
    this.autoReconnect = true,
    this.clientName = 'EZ Remote',
    this.devices = const <RemoteDevice>[],
  });

  final AppLanguage language;
  final bool autoReconnect;
  final String clientName;
  final List<RemoteDevice> devices;

  RemoteDevice? get lastDevice => devices.isEmpty ? null : devices.first;

  AppSettings copyWith({
    AppLanguage? language,
    bool? autoReconnect,
    String? clientName,
    List<RemoteDevice>? devices,
  }) {
    return AppSettings(
      language: language ?? this.language,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      clientName: clientName ?? this.clientName,
      devices: devices ?? this.devices,
    );
  }

  AppSettings withDevice(RemoteDevice device) {
    final next = <RemoteDevice>[
      device,
      ...devices.where((item) => item.id != device.id),
    ];
    return copyWith(devices: next.take(8).toList(growable: false));
  }

  AppSettings withoutDevice(String id) {
    return copyWith(
      devices: devices.where((item) => item.id != id).toList(growable: false),
    );
  }

  RemoteDevice? deviceFor(String host, int port) {
    final normalized = host.trim().toLowerCase();
    for (final device in devices) {
      if (device.port == port && device.host.toLowerCase() == normalized) {
        return device;
      }
    }
    return null;
  }
}

abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  static const _kLanguage = 'remote.language';
  static const _kAutoReconnect = 'remote.auto_reconnect';
  static const _kClientName = 'remote.client_name';
  static const _kDevices = 'remote.devices';

  Future<void> _saveQueue = Future<void>.value();

  @override
  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final language = languageFromCode(prefs.getString(_kLanguage));
      final autoReconnect = prefs.getBool(_kAutoReconnect) ?? true;
      final clientName = prefs.getString(_kClientName)?.trim() ?? '';
      final devices = <RemoteDevice>[];
      final rawDevices = prefs.getString(_kDevices);
      if (rawDevices != null && rawDevices.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawDevices);
          for (final item in jsonList(decoded)) {
            final map = jsonMap(item);
            final device = RemoteDevice.fromJson(map);
            if (device.host.trim().isNotEmpty &&
                device.token.trim().isNotEmpty) {
              devices.add(device);
            }
          }
        } catch (_) {
          // A corrupted preference should never block the app.
        }
      }
      devices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return AppSettings(
        language: language,
        autoReconnect: autoReconnect,
        clientName: clientName.isEmpty ? 'EZ Remote' : clientName,
        devices: devices,
      );
    } on Object {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) {
    // Serialize writes so a slower earlier save cannot overwrite a newer one.
    final next = _saveQueue.then((_) => _write(settings));
    _saveQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait<void>([
        prefs.setString(_kLanguage, languageCode(settings.language)),
        prefs.setBool(_kAutoReconnect, settings.autoReconnect),
        prefs.setString(_kClientName, settings.clientName.trim()),
        prefs.setString(
          _kDevices,
          jsonEncode(
            settings.devices.map((device) => device.toJson()).toList(),
          ),
        ),
      ]);
    } on Object {
      // Settings are a convenience; a storage failure must not break control.
    }
  }
}
