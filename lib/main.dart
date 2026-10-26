import 'package:flutter/material.dart';

import 'app.dart';
import 'data/settings_store.dart';
import 'data/websocket_remote_api.dart';
import 'state/remote_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = SharedPreferencesSettingsStore();
  final settings = await store.load();
  final controller = RemoteController(
    apiFactory: WebSocketRemoteApi.new,
    settingsStore: store,
    settings: settings,
  );

  runApp(RemoteApp(controller: controller));
}
