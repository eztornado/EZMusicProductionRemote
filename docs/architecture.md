# Architecture

## Goals

EZ Remote is a thin, native client for the desktop DAW. The desktop app remains
the source of truth; the phone is a low-latency control surface. That leads to a
few deliberate choices:

- No backend and no database. The app connects directly to the DAW over a LAN
  WebSocket.
- The protocol is consumed as-is; the DAW does not need remote-specific code.
- The UI is built around live snapshots and narrow `ValueNotifier`s rather than
  a global state-management package. A 20 Hz meter stream should not rebuild
  the whole workspace.
- Every command is validated by the DAW. The app shows optimistic feedback for
  continuous controls but reconciles with the next project snapshot.

## Layers

```text
┌──────────────────────────────────────────────────────────────┐
│ UI (lib/ui, lib/widgets)                                     │
│  ConnectScreen, WorkspaceScreen, Timeline, Mixer, FX, Auto   │
└───────────────────────────────┬──────────────────────────────┘
                                │ listens / calls
┌───────────────────────────────▼──────────────────────────────┐
│ RemoteController (lib/state)                                 │
│  connection lifecycle, selection, optimistic mixer, meters   │
│  transport, tracks/clips, FX, automation, error reporting    │
└───────────────────────────────┬──────────────────────────────┘
                                │ RemoteApi interface
┌───────────────────────────────▼──────────────────────────────┐
│ WebSocketRemoteApi (lib/data)                                │
│  ws:// framing, request ids, responses, push events          │
└───────────────────────────────┬──────────────────────────────┘
                                │
                    EZMusicProduction remote server
```

Supporting pieces:

- `lib/core/json.dart` — safe readers for untyped JSON.
- `lib/core/format.dart` — clock, bars/beats, dB, pan, percent and grid math.
- `lib/core/timeline_math.dart` — pure clip drag/trim/snap calculations.
- `lib/models/` — immutable snapshots of the protocol documents.
- `lib/data/discovery_service.dart` — HTTP discovery and address helpers.
- `lib/data/settings_store.dart` — `shared_preferences` persistence for the last
  device, token, language and connection options.
- `lib/l10n/strings.dart` — map-based EN/ES/JA tables and an `InheritedWidget`
  scope. No code generation.

## Protocol

The client follows `docs/design/remote-control.md` in the DAW repository.

- Every request is `{"v":1,"id":n,"cmd":"...",...}`.
- A successful response echoes `id` with `{"ok":true,"result":...}`.
- Errors echo `id` with `{"ok":false,"error":{"code":"...","message":"..."}}`.
- Push events have no `id` and use `event`/`data`.
- The first message must be `hello` with the pairing token. The server closes
  the socket after five failed attempts.
- Project snapshots are pushed at up to 8 Hz, transport at 10 Hz while running
  (0.5 Hz idle), and meters at 20 Hz after `subscribe`.

`WebSocketRemoteApi` owns request correlation and event decoding. It exposes a
sealed `RemoteEvent` stream (`ProjectEvent`, `TransportEvent`, `MetersEvent`,
`ConnectionClosedEvent`) so the controller does not parse raw JSON.

## Controller state

`RemoteController` owns:

- `connection` — phase, host, port, project name.
- `server` — welcome information and capabilities.
- `project` — latest immutable `RemoteProject`.
- `transport` — latest transport snapshot with a local receive timestamp.
- `meters` — smoothed `MeterSnapshot`.
- `plugins` — cached plugin list.
- `selectedTrackId` / `selectedClipId`.
- `preferences` — language, auto-reconnect, client name, last device.
- `error` — sequenced error objects for the app-level SnackBar.

The UI uses `ValueListenableBuilder` on the narrow notifier it needs. For
example, the mixer strips listen to `project` and `selectedTrackId`, while each
peak meter listens only to `meters`.

### Transport interpolation

The playhead is rendered between server packets by combining
`TransportState.position` with `receivedAtMicros`. `estimatedPosition` adds
elapsed time while playing and clamps to the project duration. This keeps the
playhead smooth without polling.

### Optimistic mixer

Fader and pan drags call `previewTrackVolume` / `previewTrackPan`. These:

1. update a per-track override map immediately,
2. coalesce the latest value per field into a 55 ms timer, and
3. send `mixer.setTrack` with `undo:false`.

On release, `commitTrackMix` sends the final value with `undo:true`, so the whole
drag becomes one undo entry in the DAW. Server snapshots are merged with the
override until a revision at or after the commit is observed. The master gain
uses the same idea.

### Meters

`MetersEvent` values are linear peaks. The controller applies a fast attack and
slower release and stores the result in a new `MeterSnapshot`. The meter widget
is intentionally dumb: it paints the current values and a hold line.

### Automation

Automation values are normalized `0..1` in the protocol. The automation screen
keeps a local draft while the user drags points, sends the whole lane with
`automation.set` or `automation.param.set`, then refreshes `state.get` and
reconciles. An edit generation counter prevents an older in-flight response
from clearing a newer draft.

Volume automation uses the value directly as linear gain (the DAW's engine
holds the first value before the first point and the last value after the last
point). Pan maps `0..1` to `-1..+1` for display. Sustain is a step lane.

### Errors and reconnects

All protocol errors are normalized to `RemoteApiException` with a stable code.
The controller reports them through a sequenced `error` notifier; the app shows
one SnackBar per sequence. Connection failures trigger an exponential reconnect
when auto-reconnect is enabled, with the saved token. Authentication failures
stop retrying and return to the connection screen.

## UI structure

`RemoteApp` builds the localized `MaterialApp` and the root gate:

- `ConnectScreen` when no session is open.
- `WorkspaceScreen` when connected, with an `IndexedStack` of Timeline, Mixer,
  FX and Automation.

`WorkspaceScreen` chooses a bottom navigation bar below 820 px and a navigation
rail above it. Each destination is kept alive by the `IndexedStack`, which
preserves scroll offsets and selection while switching tabs.

Shared widgets in `lib/widgets/` keep the visual language consistent:

- `GainFader` / `PanKnob` — protocol-aware continuous controls.
- `PeakMeter` — track and stereo master meters.
- `TransportBar` — global transport controls.
- `TrackChips` — compact track selector.
- `ColorPalette` — the 16-colour DAW palette.
- `SheetHeader`, `EmptyState`, `ToggleTag`, `CountBadge`, `AppIconButton`,
  `showAppSheet`, `showConfirmDialog` — consistent sheets and dialogs.

The FX screen switches from a single scrollable chain on phones to a
chain + parameter side-by-side layout at 900 px. On phones, tapping an effect
opens the parameter editor as a bottom sheet.

## Fake server

`tool/fake_server.dart` is a standalone Dart program that implements the
protocol with an in-memory project. It supports discovery, hello/token auth,
transport, mixer, track/clip edits, plugins, FX, automation and push events.
It is useful for UI work and for checking that the client does not depend on
desktop-only details.

## Testing

- `test/timeline_math_test.dart` — move/trim/snap math.
- `test/models_test.dart` — JSON parsing, clamping, copy helpers and formatting.
- `test/l10n_test.dart` — language resolution, interpolation and fallback.
- `test/network_test.dart` — endpoint parsing, IPv6 URI formatting and subnet
  discovery candidates.
- `test/remote_controller_test.dart` — pairing/auth failure, handshake close
  handling, optimistic mixer coalescing, dropped-socket cleanup, master
  coalescing, transport, meters, clip failures and phone / tablet workspace
  smoke tests.
- `test/websocket_remote_api_test.dart` — real loopback WebSocket handshake,
  request correlation, protocol errors and push-event decoding.
- `test/widget_test.dart` — shared widget smoke test.

`flutter analyze` and `flutter test` are expected to pass before a release.

## Known limitations

- Master-FX parameters cannot be edited because the protocol has no
  `fx.master.params` command.
- Instrument plugin changes and clip mute changes are not exposed by the
  protocol.
- The app intentionally uses cleartext `ws://`; it is a LAN-only tool.
- A release APK needs a signing configuration and an Android SDK/JDK on the
  build machine.
