# EZMusicProductionRemote

A native Flutter remote for **EZMusicProduction**. It turns an Android phone or
tablet — or an iPad — into a transport, timeline, mixer, FX and automation
surface for a DAW running on the local network.

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
- **Synth** — dedicated instrument surface with EZSynth 2 factory presets,
  grouped page tabs (layers, filters, envelopes, modulation, FX, arp, macros
  and expression) and switch/choice/integer-aware controls.
- **FX** — insert chains per track, instrument parameters, bypass, add/remove,
  master chain management with parameter editing and a throttled editor.
- **Automation** — volume, pan and sustain lanes plus plugin-parameter lanes;
  add points by tapping, shape them by dragging, delete with a long press, and
  write volume at the playhead.
- **Project** — undo/redo, track creation/removal, rename, colour and input
  channel.
- **Settings** — desktop-style sectioned preferences: connection, interface
  (language), security and about.
- **Live state** — project, transport and 20 Hz meters are pushed by the DAW.
- **Adaptive UI** — bottom navigation on phones, a navigation rail on tablets,
  and side-by-side FX editing on wide screens.
- **Localized** — English, Spanish and Japanese, following the system language
  by default.
- **Resilient connection** — LAN discovery, pairing code, saved device,
  automatic reconnect and clear protocol errors.

## Requirements

- Flutter 3.29 or newer with Dart 3.7 or newer.
- Android 5.0 (API 21) or newer, or iPadOS 12 or newer.
- The DAW's remote server enabled in **Preferences → Remote control**.
- The phone/tablet and the computer on the same trusted LAN.
- For Android builds: the Android SDK and a JDK (17 recommended).
- For iOS/iPad builds: macOS, Xcode 15 or newer and CocoaPods.

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

### Build from GitHub Actions

The CI workflow builds a debug APK on every push to `main`, on pull requests and
when a new tag is created. To build one on demand, open **Actions → CI → Run
workflow**. Once the run finishes, download
**`ezmusicproductionremote-debug-apk`** from the run's **Artifacts** section. The
APK is debug-signed and installable on test devices; use a `v*` tag release for a
release-signed APK.

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

### Tag releases

Pushing a tag like `v26.11.01.02` runs the release workflow, which builds an
APK and attaches it to a GitHub release for that tag. To publish
release-signed APKs from CI, add four repository secrets:
`ANDROID_KEYSTORE_BASE64` (the keystore file, base64 encoded with
`base64 -i android/keystore/ez-remote-release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Without them the workflow
falls back to a debug-signed APK, which is clearly labelled as such in the
release notes.

## Build iPad / iOS

The project includes an iOS target that supports both iPhone and iPad. Building
it requires macOS with Xcode 15 or newer and CocoaPods:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

Running on a physical iPad requires an Apple development team for signing. A
free Apple ID works for local development but the app expires after seven days;
TestFlight and App Store distribution require the Apple Developer Program.

The app uses the local network to find and control the DAW. On iOS/iPadOS the
system asks for local network permission on first use; the required usage
description and local-networking ATS exception are already configured in
`ios/Runner/Info.plist`.

### iOS / iPad from GitHub Actions

The `iOS / iPad` workflow runs on new tags and can be started manually from
**Actions → iOS / iPad → Run workflow**. It always publishes an unsigned
`Runner.app` archive so the iOS target is compile-checked.

If these repository secrets are configured, the workflow also builds and
uploads a signed IPA:

- `IOS_CERTIFICATE_BASE64` — base64 of the `.p12` signing certificate.
- `IOS_CERTIFICATE_PASSWORD` — password for the `.p12`.
- `IOS_PROVISIONING_PROFILE_BASE64` — base64 of the matching `.mobileprovision`.
- `APPLE_TEAM_ID` — Apple Developer team identifier.

The optional `IOS_EXPORT_METHOD` repository variable selects the export method
when the workflow is triggered by a tag: `development`, `ad-hoc`, `app-store` or
`enterprise`. Manual runs can choose it in the workflow form. The provisioning
profile must match the bundle identifier
`com.ezmusicproduction.ezmusicproductionRemote` and the signing certificate.

Without the signing secrets, the unsigned artifact verifies the build but
cannot be installed on an iPad.

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

---

# EZMusicProductionRemote (Español)

Un control remoto nativo en Flutter para **EZMusicProduction**. Convierte un teléfono
o tableta Android — o un iPad — en una superficie de transporte, línea de tiempo,
mezclador, efectos y automatización para una DAW ejecutándose en la red local.

La aplicación es un cliente independiente para la API remota WebSocket + JSON de la DAW. No
requiere un backend, una cuenta en la nube ni un plugin en el proyecto de escritorio.

## Características

- **Transporte** — reproducir, pausa, detener, grabar, buscar, metrónomo, tempo y
  compás.
- **Línea de tiempo** — regla sincronizada, encabezados de pista y lienzo de clips; seleccionar,
  mover, recortar, dividir y editar límites de clips, fundidos y ganancia.
- **Mezclador** — canales con faders, panorámica, mute/solo/armado de grabación, indicadores de pico
  y un canal maestro. Los arrastres continuos de fader y panorámica se convierten en una entrada de deshacer
  al soltar.
- **Sintetizador** — superficie de instrumento dedicada con presets de fábrica EZSynth 2,
  pestañas de página agrupadas (capas, filtros, envolventes, modulación, efectos, arp, macros
  y expresión) y controles conscientes de interruptor/elección/entero.
- **Efectos** — cadenas de inserción por pista, parámetros de instrumento, bypass, agregar/eliminar,
  gestión de cadena maestra con edición de parámetros y un editor con throttling.
- **Automatización** — carriles de volumen, panorámica y sustain más carriles de parámetros de plugin;
  agregar puntos tocando, darles forma arrastrando, eliminar con una pulsación larga, y
  escribir volumen en el puntero de reproducción.
- **Proyecto** — deshacer/rehacer, creación/eliminación de pistas, renombrar, color y
  canal de entrada.
- **Configuración** — preferencias seccionadas estilo escritorio: conexión, interfaz
  (idioma), seguridad e información.
- **Estado en vivo** — proyecto, transporte y medidores a 20 Hz son enviados por la DAW.
- **UI adaptativa** — navegación inferior en teléfonos, riel de navegación en tabletas,
  y edición de efectos lado a lado en pantallas anchas.
- **Localizado** — inglés, español y japonés, siguiendo el idioma del sistema
  por defecto.
- **Conexión resistente** — descubrimiento en LAN, código de emparejamiento, dispositivo guardado,
  reconexión automática y mensajes claros de errores de protocolo.

## Requisitos

- Flutter 3.29 o superior con Dart 3.7 o superior.
- Android 5.0 (API 21) o superior, o iPadOS 12 o superior.
- El servidor remoto de la DAW habilitado en **Preferencias → Control remoto**.
- El teléfono/tableta y el ordenador en la misma LAN de confianza.
- Para compilaciones Android: el SDK de Android y un JDK (17 recomendado).
- Para compilaciones iOS/iPad: macOS, Xcode 15 o superior y CocoaPods.

## Ejecutar la aplicación

```bash
flutter pub get
flutter run
```

La pantalla de conexión admite dos flujos de trabajo:

1. **Escanear red** para encontrar un estudio a través del endpoint de descubrimiento HTTP de la DAW.
2. Ingresar la dirección IP y el puerto del ordenador manualmente (por defecto `47823`), luego
   ingresar el código de emparejamiento mostrado en la DAW.

El código de emparejamiento es la única barrera de autenticación a nivel de aplicación. Trátalo
como una contraseña y nunca expongas el puerto remoto a internet público.

## Ejecutar sin la DAW

Se incluye un estudio falso compatible con el protocolo para trabajo de UI y demostraciones:

```bash
dart run tool/fake_server.dart
# o elige un puerto y código de emparejamiento
dart run tool/fake_server.dart --port=47823 --token=123456
```

Sirve descubrimiento en `http://<host>:47823/` y WebSocket en
`ws://<host>:47823/`, con un proyecto en memoria, lista de plugins, medidores y
automatización. El token por defecto es un valor de demostración; no lo reutilices para un
estudio real.

- **Emulador Android:** conecta a `10.0.2.2`.
- **Dispositivo físico:** usa la dirección LAN impresa por el servidor falso y asegúrate
  de que el firewall del host permita conexiones entrantes en el puerto.

## Compilar para Android

Las compilaciones de depuración funcionan sin ninguna configuración de firma:

```bash
flutter build apk --debug
```

### Compilar desde GitHub Actions

El flujo de CI compila un APK de depuración en cada push a `main`, en pull requests y
cuando se crea una nueva etiqueta. Para compilar uno bajo demanda, abre **Actions → CI → Run
workflow**. Una vez finalizada la ejecución, descarga
**`ezmusicproductionremote-debug-apk`** de la sección **Artifacts** de la ejecución. El
APK está firmado como depuración e instalable en dispositivos de prueba; usa una etiqueta `v*` para un
APK firmado para producción.

### Firma de release

Las compilaciones de release deben usar tu propia clave privada. El proyecto deliberadamente **no
tiene fallback a debug-key para compilaciones de release**: si la firma no está configurada, la
compilación de release falla en lugar de producir un APK instalable pero no confiable.

1. Crea un keystore fuera del control de versiones (el ejemplo de abajo lo mantiene en
   `android/keystore/`, que es ignorado por Git):

   ```bash
   mkdir -p android/keystore
   keytool -genkeypair -v \
     -keystore android/keystore/ez-remote-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias ez-remote
   ```

2. Copia la configuración de ejemplo y rellena tus valores:

   ```bash
   cp android/key.properties.example android/key.properties
   ```

   `android/key.properties` y el keystore son ignorados por Git. Nunca commitees
   ninguno de ellos. La ruta `storeFile` se resuelve relativa a
   `android/app/`.

3. Compila un app bundle o APK firmado:

   ```bash
   flutter build appbundle --release
   # o
   flutter build apk --release
   ```

Mantén el keystore y las contraseñas en un respaldo seguro. Si se pierde una clave de firma,
no puedes publicar actualizaciones para el mismo ID de aplicación. Si se expone,
rotala y usa un nuevo ID de aplicación.

### Releases con etiqueta

Empujar una etiqueta como `v26.11.01.02` ejecuta el flujo de release, que compila un
APK y lo adjunta a un release de GitHub para esa etiqueta. Para publicar
APKs firmados para release desde CI, agrega cuatro secretos de repositorio:
`ANDROID_KEYSTORE_BASE64` (el archivo keystore, codificado en base64 con
`base64 -i android/keystore/ez-remote-release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`. Sin ellos el flujo
recurre a un APK firmado como depuración, que está claramente etiquetado como tal en las
notas de release.

## Compilar para iPad / iOS

El proyecto incluye un objetivo iOS que soporta iPhone e iPad. Compilarlo
requiere macOS con Xcode 15 o superior y CocoaPods:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

Ejecutar en un iPad físico requiere un equipo de desarrollo de Apple para la firma. Un
Apple ID gratuito funciona para desarrollo local pero la aplicación expira después de siete días;
TestFlight y distribución en App Store requieren el Apple Developer Program.

La aplicación usa la red local para encontrar y controlar la DAW. En iOS/iPadOS el
sistema pide permiso de red local en el primer uso; la descripción de uso requerida y
la excepción ATS de red local ya están configuradas en
`ios/Runner/Info.plist`.

### iOS / iPad desde GitHub Actions

El flujo `iOS / iPad` se ejecuta en nuevas etiquetas y puede iniciarse manualmente desde
**Actions → iOS / iPad → Run workflow**. Siempre publica un archivo
`Runner.app` sin firmar para que el objetivo iOS sea verificado en compilación.

Si estos secretos de repositorio están configurados, el flujo también compila y
sube un IPA firmado:

- `IOS_CERTIFICATE_BASE64` — base64 del certificado de firma `.p12`.
- `IOS_CERTIFICATE_PASSWORD` — contraseña del `.p12`.
- `IOS_PROVISIONING_PROFILE_BASE64` — base64 del `.mobileprovision` coincidente.
- `APPLE_TEAM_ID` — identificador del equipo de Apple Developer.

La variable de repositorio opcional `IOS_EXPORT_METHOD` selecciona el método de exportación
cuando el flujo es activado por una etiqueta: `development`, `ad-hoc`, `app-store` o
`enterprise`. Las ejecuciones manuales pueden elegirlo en el formulario del flujo. El perfil de
provisionamiento debe coincidir con el identificador del paquete
`com.ezmusicproduction.ezmusicproductionRemote` y el certificado de firma.

Sin los secretos de firma, el artefacto sin firmado verifica la compilación pero
no puede instalarse en un iPad.

## Notas de seguridad

- Este cliente usa el protocolo LAN de la DAW sobre `ws://`; TLS no está
  soportado intencionalmente porque la API remota de escritorio es solo LAN. No expongas el
  puerto remoto a través de un router, túnel o proxy inverso público.
- Los códigos de emparejamiento son credenciales de aplicación de corta duración, no
  cifrado de transporte. Usa la aplicación solo en una red local de confianza.
- El material de firma de release nunca debe ser commiteado. El `.gitignore`
  del repositorio excluye `key.properties`, keystores y archivos de secretos comunes.
- El servidor falso y su token por defecto son solo para desarrollo local.

## Pruebas

```bash
flutter analyze
flutter test
```

El conjunto de pruebas cubre matemáticas de arrastre/snap de línea de tiempo, modelos de protocolo y limitación,
formateo, localización, análisis de endpoints y candidatos de descubrimiento, handshakes de controlador
y comportamiento optimista del mezclador, manejo real de solicitudes/eventos WebSocket, y
pruebas de workspace en teléfono/tableta.

## Estructura del proyecto

```text
lib/
  core/          JSON, formateo, red y matemáticas de línea de tiempo
  data/          Cliente WebSocket, descubrimiento y persistencia de configuración
  l10n/          Tablas de cadenas EN/ES/JA
  models/        Modelos inmutables de proyecto, transporte, medidor y plugin
  state/         RemoteController: protocolo, reconexión y mezclador optimista
  theme/         Paleta oscura compartida con la aplicación de escritorio
  ui/            Conexión, workspace, línea de tiempo, mezclador, efectos y automatización
  widgets/       Faders, medidores, chips, sheets y barra de transporte compartidos
tool/
  fake_server.dart   Estudio falso compatible con el protocolo local
test/              Pruebas unitarias y de widgets
docs/              Notas de arquitectura
android/           Empaquetado Android, recursos y ejemplo de firma
```

## Protocolo

El cliente consume el protocolo de control remoto de EZMusicProduction tal cual:

- Las solicitudes son objetos JSON con una versión de protocolo, ID de solicitud y comando.
- Las respuestas exitosas repiten el ID de solicitud y devuelven `result`.
- Los errores repiten el ID de solicitud y devuelven un código y mensaje de error.
- Los eventos push no tienen ID de solicitud y llevan su carga bajo `data`.
- El primer mensaje es `hello` con el token de emparejamiento.
- Las instantáneas de proyecto se envían a hasta 8 Hz, el transporte a 10 Hz mientras se ejecuta
  y 0.5 Hz en reposo, y los medidores a 20 Hz después de `subscribe`.

## Limitaciones

- Sin transmisión o monitoreo de audio.
- Sin edición MIDI nota por nota.
- Sin emparejamiento en la nube, TLS o acceso remoto fuera de la LAN.
- Sin edición de parámetros de efectos maestros (el protocolo solo expone agregar/eliminar/bypass).
- Sin comando para cambiar el plugin de instrumento de una pista o la bandera de mute de un clip.

---

# EZMusicProductionRemote (日本語)

**EZMusicProduction**用のネイティブFlutterリモートコントローラーです。Androidスマートフォンや
タブレット、またはiPadを、ローカルネットワーク上で動作するDAWのトランスポート、タイムライン、ミキサー、エフェクトおよびオートメーションの操作インターフェースに変えます。

このアプリはDAWのWebSocket + JSONリモートAPIのためのスタンドアロンクライアントです。
バックエンド、クラウドアカウント、またはデスクトッププロジェクトのプラグインは不要です。

## 機能

- **トランスポート** — 再生、一時停止、停止、録音、シーク、メトロノーム、テンポおよび
  拍子。
- **タイムライン** — 同期されたルール、トラックヘッダーおよびクリップキャンバス; クリップの選択、
  移動、トリム、分割、境界、フェードおよびゲインの編集。
- **ミキサー** — フェーダー、パン、ミュート/ソロ/録音スタンバイ、ピークメーターおよび
  マスターチャンネルを備えたチャンネルストリップ。フェーダーとパンの連続ドラッグは、
  離したときに1つのアンドゥエントリになります。
- **シンセサイザー** — EZSynth 2ファクトリープリセットを備えた専用楽器インターフェース、
  グループ化されたページタブ（レイヤー、フィルター、エンベロープ、モジュレーション、エフェクト、アルペジエーター、マクロ
  およびエクスプレッション）、およびスイッチ/チョイス/整数対応コントロール。
- **エフェクト** — トラックごとのインサートチェーン、楽器パラメータ、バイパス、追加/削除、
  パラメータ編集およびスロットル付きエディターを備えたマスターチェーン管理。
- **オートメーション** — ボリューム、パン、サステインレーンおよびプラグインパラメータレーン;
  タップでポイントを追加、ドラッグでシェイプ、長押しで削除、
  プレイヘッドでボリュームを書き込み。
- **プロジェクト** — アンドゥ/リドゥ、トラックの作成/削除、名前変更、カラーおよび
  入力チャンネル。
- **設定** — デスクトップスタイルのセクション別設定: 接続、インターフェース
  （言語）、セキュリティおよびバージョン情報。
- **ライブ状態** — プロジェクト、トランスポートおよび20 HzメーターはDAWによってプッシュされます。
- **アダプティブUI** — スマートフォンではボトムナビゲーション、タブレットではナビゲーションレール、
  ワイド画面では並列エフェクト編集。
- **ローカライズ** — 英語、スペイン語、日本語、デフォルトでシステム言語に従います。
- **堅牢な接続** — LAN発見、ペアリングコード、保存されたデバイス、
  自動再接続および明確なプロトコルエラーメッセージ。

## 要件

- Flutter 3.29以降、Dart 3.7以降。
- Android 5.0（API 21）以降、またはiPadOS 12以降。
- **Preferences → Remote control**でDAWのリモートサーバーが有効化されていること。
- スマートフォン/タブレットとコンピュータが同じ信頼できるLAN上にいること。
- Androidビルド用: Android SDKおよびJDK（17を推奨）。
- iOS/iPadビルド用: macOS、Xcode 15以降およびCocoaPods。

## アプリの実行

```bash
flutter pub get
flutter run
```

接続画面は2つのワークフローをサポートしています:

1. **ネットワークスキャン** でDAWのHTTP発見エンドポイントを通じてスタジオを検索。
2. コンピュータのIPアドレスとポートを手動で入力（デフォルト `47823`）、次に
   DAWに表示されるペアリングコードを入力。

ペアリングコードはアプリケーションレベルの唯一の認証バリアです。パスワードのように扱い、
リモートポートを公開インターネットに決して公開しないでください。

## DAWなしで実行

UI作業とデモ用のプロトコル互換のフェイクスタジオが含まれています:

```bash
dart run tool/fake_server.dart
# またはポートとペアリングコードを選択
dart run tool/fake_server.dart --port=47823 --token=123456
```

`http://<host>:47823/`で発見、`ws://<host>:47823/`でWebSocketを提供し、
インメモリプロジェクト、プラグインリスト、メーターおよび
オートメーションを備えています。デフォルトトークンはデモ値です; 本番スタジオで
再利用しないでください。

- **Androidエミュレーター:** `10.0.2.2`に接続。
- **物理デバイス:** フェイクサーバーが表示するLANアドレスを使用し、
  ホストファイアウォールがポートへの着信接続を許可していることを確認。

## Androidのビルド

デバッグビルドは署名設定なしで動作します:

```bash
flutter build apk --debug
```

### GitHub Actionsからのビルド

CIワークフローは`main`へのプッシュ、プルリクエストおよび
新しいタグの作成時にデバッグAPKをビルドします。オンデマンドでビルドするには、**Actions → CI → Run
workflow**を開きます。実行が完了したら、
実行の**Artifacts**セクションから**`ezmusicproductionremote-debug-apk`**をダウンロードします。APKは
デバッグ署名されておりテストデバイスにインストール可能です; リリース署名APKには`v*`タグを使用します。

### リリース署名

リリースビルドは独自の秘密鍵を使用する必要があります。プロジェクトは意図的に**リリースビルドの
debug-keyフォールバックを持っていません**: 署名が設定されていない場合、
リリースビルドはインストール可能だが信頼できないAPKを生成するのではなく失敗します。

1. バージョン管理の外にキーストアを作成（以下の例はGitで無視されている
   `android/keystore/`に保持）:

   ```bash
   mkdir -p android/keystore
   keytool -genkeypair -v \
     -keystore android/keystore/ez-remote-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias ez-remote
   ```

2. 例の設定をコピーして値を入力:

   ```bash
   cp android/key.properties.example android/key.properties
   ```

   `android/key.properties`とキーストアはGitで無視されます。決してコミットしないでください。`storeFile`パスは
   `android/app/`に対して相対的に解決されます。

3. 署名されたアプリバンドルまたはAPKをビルド:

   ```bash
   flutter build appbundle --release
   # または
   flutter build apk --release
   ```

キーストアとパスワードを安全なバックアップに保管してください。署名鍵が失われた場合、
同じアプリケーションIDのアップデートを公開できません。公開された場合は、
ローテーションして新しいアプリケーションIDを使用してください。

### タグリリース

`v26.11.01.02`のようなタグをプッシュするとリリースワークフローが実行され、
APKをビルドしてそのタグのGitHubリリースに添付します。CIから
リリース署名APKを公開するには、4つのリポジトリシークレットを追加します:
`ANDROID_KEYSTORE_BASE64`（キーストアファイル、base64エンコード
`base64 -i android/keystore/ez-remote-release.jks`）、`ANDROID_KEYSTORE_PASSWORD`、
`ANDROID_KEY_ALIAS`および`ANDROID_KEY_PASSWORD`。これらがない場合、ワークフローは
デバッグ署名APKにフォールバックし、リリースノートで明確にラベル付けされます。

## iPad / iOSのビルド

プロジェクトにはiPhoneとiPadの両方をサポートするiOSターゲットが含まれています。ビルドには
macOS、Xcode 15以降およびCocoaPodsが必要です:

```bash
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
```

物理iPadでの実行にはApple開発チームの署名が必要です。無料のApple IDはローカル開発に機能しますが、
アプリは7日後に期限切れになります; TestFlightおよびApp Store配布にはApple Developer Programが必要です。

アプリはローカルネットワークを使用してDAWを検索および制御します。iOS/iPadOSでは
システムは初回使用時にローカルネットワーク権限を要求します; 必要な使用説明およびローカルネットワークATS例外は
`ios/Runner/Info.plist`ですでに設定されています。

### GitHub ActionsからのiOS / iPad

`iOS / iPad`ワークフローは新しいタグで実行され、**Actions → iOS / iPad → Run
workflow**から手動で開始できます。iOSターゲットがコンパイルチェックされるように、常に署名なしの
`Runner.app`アーカイブを公開します。

これらのリポジトリシークレットが設定されている場合、ワークフローは署名付きIPAもビルドおよび
アップロードします:

- `IOS_CERTIFICATE_BASE64` — `.p12`署名証明書のbase64。
- `IOS_CERTIFICATE_PASSWORD` — `.p12`のパスワード。
- `IOS_PROVISIONING_PROFILE_BASE64` — 一致する`.mobileprovision`のbase64。
- `APPLE_TEAM_ID` — Apple Developerチーム識別子。

オプションの`IOS_EXPORT_METHOD`リポジトリ変数は、タグによってワークフローがトリガーされたときにエクスポート方法を
選択します: `development`、`ad-hoc`、`app-store`または`enterprise`。手動実行はワークフローフォームで選択できます。プロビジョニング
プロファイルはバンドル識別子
`com.ezmusicproduction.ezmusicproductionRemote`および署名証明書と一致する必要があります。

署名シークレットなしでは、署名なしアーティファクトはビルドを検証しますが
iPadにインストールできません。

## セキュリティに関する注意

- このクライアントはDAWのLANプロトコルを`ws://`で使用します; TLSは意図的に
  サポートされていません。デスクトップリモートAPIはLANのみです。ルーター、トンネルまたは公開リバースプロキシを通じて
  リモートポートを公開しないでください。
- ペアリングコードは短命のアプリケーション認証情報であり、トランスポート
  暗号化ではありません。信頼できるローカルネットワークでのみアプリを使用してください。
- リリース署名素材は決してコミットしないでください。リポジトリの
  `.gitignore`は`key.properties`、キーストアおよび一般的なシークレットファイルを除外します。
- フェイクサーバーとそのデフォルトトークンはローカル開発用のみです。

## テスト

```bash
flutter analyze
flutter test
```

テストスイートはタイムラインのドラッグ/スナップ数学、プロトコルモデルおよびクランピング、
フォーマット、ローカライゼーション、エンドポイント解析および発見候補、コントローラー
ハンドシェイクおよび楽観的ミキサー動作、実際のWebSocketリクエスト/イベント
処理、およびスマートフォン/タブレットワークスペースのスモークテストをカバーしています。

## プロジェクト構成

```text
lib/
  core/          JSON、フォーマット、ネットワークおよびタイムライン数学
  data/          WebSocketクライアント、発見および設定永続化
  l10n/          EN/ES/JA文字列表
  models/        不変プロジェクト、トランスポート、メーターおよびプラグインモデル
  state/         RemoteController: プロトコル、再接続および楽観的ミキサー
  theme/         デスクトップアプリと共有されるダークパレット
  ui/            接続、ワークスペース、タイムライン、ミキサー、エフェクトおよびオートメーション
  widgets/       共有フェーダー、メーター、チップ、シートおよびトランスポートバー
tool/
  fake_server.dart   ローカルプロトコル互換フェイクスタジオ
test/              ユニットおよびウィジェットテスト
docs/              アーキテクチャノート
android/           Androidエンベディング、リソースおよび署名例
```

## プロトコル

クライアントはEZMusicProductionのリモートコントロールプロトコルをそのまま消費します:

- リクエストはプロトコルバージョン、リクエストIDおよびコマンドを持つJSONオブジェクトです。
- 成功したレスポンスはリクエストIDをエコーし、`result`を返します。
- エラーはリクエストIDをエコーし、エラーコードとメッセージを返します。
- プッシュイベントはリクエストIDを持たず、ペイロードを`data`の下に保持します。
- 最初のメッセージはペアリングトークン付きの`hello`です。
- プロジェクトスナップショットは最大8 Hzで、トランスポートは実行中に10 Hz、
  アイドル時に0.5 Hzで、メーターは`subscribe`後に20 Hzでプッシュされます。

## 制限事項

- オーディオストリーミングまたはモニタリングなし。
- ノートバイノートのMIDI編集なし。
- クラウドペアリング、TLSまたはLAN外のリモートアクセスなし。
- マスターエフェクトパラメータ編集なし（プロトコルは追加/削除/バイパスのみを公開）。
- トラックの楽器プラグインまたはクリップのミュートフラグを変更するコマンドなし。
