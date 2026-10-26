# EZ Remote

A native Flutter Android remote for **EZMusicProduction**. It turns an Android
phone or tablet into a transport, timeline, mixer, FX and automation surface for
a DAW running on the local network.

The app is a standalone client for the DAW's WebSocket + JSON remote API. It
does not require a backend, a cloud account or a plugin in the desktop project.

## Features

- **Transport** — play, pause, stop, record, seek, metronome, tempo and time
  signature.
- **Timeline** — synchronized ruler, track headers and clip canvas; select,
  move, trim, split and edit clip bounds, fades and gain.
- **Mixer** — channel strips with faders, pan, mute/solo/record-arm, peak meters
  and a master strip. Continuous fader and pan drags become one undo entry when
  released.
- **FX** — insert chains per track, instrument parameters, bypass, add/remove,
  master chain management and a throttled parameter editor.
- **Automation** — volume, pan and sustain lanes plus plugin-parameter lanes;
  add points by tapping, shape them by dragging, delete with a long press, and
  write volume at the playhead.
- **Project** — undo/redo, track creation/removal, rename, colour and input
  channel.
- **Live state** — project, transport and 20 Hz meters are pushed by the DAW.
- **Adaptive UI** — bottom navigation on phones, a navigation rail on tablets,
  and side-by-side FX editing on wide screens.
- **Localized** — English, Spanish and Japanese, following the system language
  by default.
- **Resilient connection** — LAN discovery, pairing code, saved device,
  automatic reconnect and clear protocol errors.

## Requirements

- Flutter 3.29 or newer with Dart 3.7 or newer.
- Android 5.0 (API 21) or newer.
- The DAW's remote server enabled in **Preferences → Remote control**.
- The phone/tablet and the computer on the same trusted LAN.
- For Android builds: the Android SDK and a JDK (17 recommended).

## Run the app

```bash
flutter pub get
flutter run
```

The connection screen supports two workflows:

1. **Scan network** to find a studio through the DAW's HTTP discovery endpoint.
2. Enter the computer's IP address and port manually (default `47823`), then
   enter the pairing code shown in the DAW.

The pairing code is the only application-level authentication barrier. Treat it
like a password and never expose the remote port to the public internet.

## Run without the DAW

A protocol-compatible fake studio is included for UI work and demos:

```bash
dart run tool/fake_server.dart
# or choose a port and pairing code
dart run tool/fake_server.dart --port=47823 --token=123456
```

It serves discovery on `http://<host>:47823/` and the WebSocket on
`ws://<host>:47823/`, with an in-memory project, plugin list, meters and
automation. The default token is a demo value; do not reuse it for a real
studio.

- **Android emulator:** connect to `10.0.2.2`.
- **Physical device:** use the LAN address printed by the fake server and make
  sure the host firewall allows incoming connections on the port.

## Build Android

Debug builds work without any signing setup:

```bash
flutter build apk --debug
```

### Release signing

Release builds must use your own private key. The project deliberately has **no
debug-key fallback for release builds**: if signing is not configured, the
release build fails instead of producing an installable but untrustworthy APK.

1. Create a keystore outside version control (the example below keeps it in
   `android/keystore/`, which is ignored by Git):

   ```bash
   mkdir -p android/keystore
   keytool -genkeypair -v \
     -keystore android/keystore/ez-remote-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias ez-remote
   ```

2. Copy the example configuration and fill in your values:

   ```bash
   cp android/key.properties.example android/key.properties
   ```

   `android/key.properties` and the keystore are ignored by Git. Never commit
   either of them. The `storeFile` path is resolved relative to
   `android/app/`.

3. Build a signed app bundle or APK:

   ```bash
   flutter build appbundle --release
   # or
   flutter build apk --release
   ```

Keep the keystore and passwords in a secure backup. If a signing key is lost,
you cannot publish updates for the same application ID. If it is exposed,
rotate it and use a new application ID.

## Security notes

- This client speaks the DAW's LAN protocol over `ws://`; TLS is intentionally
  not supported because the desktop remote API is LAN-only. Do not expose the
  remote port through a router, tunnel or public reverse proxy.
- Pairing codes are short-lived application credentials, not transport
  encryption. Use the app only on a trusted local network.
- Release signing material must never be committed. The repository's
  `.gitignore` excludes `key.properties`, keystores and common secret files.
- The fake server and its default token are for local development only.

## Tests

```bash
flutter analyze
flutter test
```

The test suite covers timeline drag/snap math, protocol models and clamping,
formatting, localization, endpoint parsing and discovery candidates, controller
handshakes and optimistic mixer behaviour, real WebSocket request/event
handling, and phone/tablet workspace smoke tests.

## Project layout

```text
lib/
  core/          JSON, formatting, network and timeline math
  data/          WebSocket client, discovery and settings persistence
  l10n/          EN/ES/JA string tables
  models/        Immutable project, transport, meter and plugin models
  state/         RemoteController: protocol, reconnect and optimistic mixer
  theme/         Dark palette shared with the desktop app
  ui/            Connect, workspace, timeline, mixer, FX and automation
  widgets/       Shared faders, meters, chips, sheets and transport bar
tool/
  fake_server.dart   Local protocol-compatible fake studio
test/              Unit and widget tests
docs/              Architecture notes
android/           Android embedding, resources and signing example
```

## Protocol

The client consumes the EZMusicProduction remote-control protocol as-is:

- Requests are JSON objects with a protocol version, request ID and command.
- Successful responses echo the request ID and return `result`.
- Errors echo the request ID and return an error code and message.
- Push events have no request ID and carry their payload under `data`.
- The first message is `hello` with the pairing token.
- Project snapshots are pushed at up to 8 Hz, transport at 10 Hz while running
  and 0.5 Hz when idle, and meters at 20 Hz after `subscribe`.

## Limitations

- No audio streaming or monitoring.
- No note-by-note MIDI editing.
- No cloud pairing, TLS or remote access outside the LAN.
- No master-FX parameter editing (the protocol only exposes add/remove/bypass).
- No command for changing a track's instrument plugin or a clip's mute flag.
