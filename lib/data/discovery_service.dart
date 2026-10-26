import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../core/json.dart';
import '../core/network.dart';
import '../models/session.dart';

/// Finds EZMusicProduction studios on the local network by probing the HTTP
/// discovery endpoint (§3.1) across the /24 networks this device is attached
/// to. No broadcast or special Android permission is required.
class DiscoveryService {
  DiscoveryService({this.port = 47823, this.concurrency = 32});

  final int port;
  final int concurrency;

  Stream<DiscoveredServer> scan({int? portOverride}) {
    final scanPort = portOverride ?? port;
    late StreamController<DiscoveredServer> controller;
    final client =
        HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 380)
          ..idleTimeout = const Duration(seconds: 2)
          ..userAgent = 'EZRemote/0.1';
    var cancelled = false;

    Future<void> run() async {
      try {
        final hosts = await _candidateHosts();
        final queue = ListQueue<String>.of(hosts);
        Future<void> worker() async {
          while (!cancelled && queue.isNotEmpty) {
            final host = queue.removeFirst();
            final server = await _probe(host, scanPort, client);
            if (server != null && !cancelled && !controller.isClosed) {
              controller.add(server);
            }
          }
        }

        final workers = List<Future<void>>.generate(
          concurrency.clamp(1, 64),
          (_) => worker(),
        );
        await Future.wait(workers);
      } catch (error) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error);
        }
      } finally {
        client.close(force: true);
        if (!cancelled && !controller.isClosed) {
          await controller.close();
        }
      }
    }

    controller = StreamController<DiscoveredServer>(
      onListen: () {
        unawaited(run());
      },
      onCancel: () {
        cancelled = true;
        client.close(force: true);
      },
    );
    return controller.stream;
  }

  Future<List<String>> _candidateHosts() async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          addresses.add(address.address);
        }
      }
    } on Object {
      // Wi-Fi may be off; the emulator alias still gives us one candidate.
    }

    final prefixes = localSubnetPrefixes(addresses);
    final local = addresses.toSet();
    final hosts = <String>{};
    for (final prefix in prefixes) {
      for (var last = 1; last <= 254; last++) {
        final host = '$prefix.$last';
        if (host == '127.0.0.1') continue;
        if (local.contains(host)) continue;
        hosts.add(host);
      }
    }
    // Android emulator: 10.0.2.2 is the host Mac.
    hosts.add('10.0.2.2');
    return hosts.toList(growable: false);
  }

  Future<DiscoveredServer?> _probe(
    String host,
    int port,
    HttpClient client,
  ) async {
    try {
      final request = await client
          .getUrl(Uri.parse(httpDiscoveryUri(host, port)))
          .timeout(const Duration(milliseconds: 900));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(
        const Duration(milliseconds: 900),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(milliseconds: 1200));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final json = jsonMap(decoded);
      final app = jsonString(json['app']);
      final transport = jsonString(json['transport']);
      final looksLikeStudio =
          app.toLowerCase().contains('ezmusicproduction') ||
          (transport == 'websocket+json' && json.containsKey('protocol'));
      if (!looksLikeStudio) return null;
      return DiscoveredServer.fromDiscovery(json, host: host, port: port);
    } on Object {
      return null;
    }
  }

  /// Validates a manually typed endpoint without opening a WebSocket.
  Future<DiscoveredServer?> probeEndpoint(Endpoint endpoint) async {
    final client =
        HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 900)
          ..userAgent = 'EZRemote/0.1';
    try {
      return await _probe(endpoint.host, endpoint.port, client);
    } finally {
      client.close(force: true);
    }
  }
}
