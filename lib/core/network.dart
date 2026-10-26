import 'dart:io';

/// Address parsing shared by the connect screen and the WebSocket client.
class Endpoint {
  const Endpoint(this.host, this.port);

  final String host;
  final int port;

  String get label => '$host:$port';
}

/// Accepts plain hosts (`192.168.1.20`, `studio.local`), `host:port` and full
/// WebSocket URLs (`ws://192.168.1.20:47823/`). Returns `null` for empty or
/// obviously invalid input.
Endpoint? parseEndpointInput(String raw, {int defaultPort = 47823}) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  if (value.contains('://')) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'ws' && uri.scheme != 'http') {
      return null;
    }
    final port = uri.hasPort ? uri.port : defaultPort;
    if (!_validPort(port)) return null;
    return Endpoint(_normalizeHost(uri.host), port);
  }

  // Bare IPv6 in brackets, with an optional port.
  if (value.startsWith('[')) {
    final close = value.indexOf(']');
    if (close < 0) return null;
    final host = value.substring(1, close);
    final address = InternetAddress.tryParse(host);
    if (address == null || address.type != InternetAddressType.IPv6) {
      return null;
    }
    final rest = value.substring(close + 1);
    var port = defaultPort;
    if (rest.startsWith(':')) {
      final parsed = int.tryParse(rest.substring(1));
      if (parsed == null || !_validPort(parsed)) return null;
      port = parsed;
    } else if (rest.isNotEmpty) {
      return null;
    }
    return Endpoint(host, port);
  }

  final colonCount = ':'.allMatches(value).length;
  if (colonCount == 1) {
    final split = value.lastIndexOf(':');
    final host = value.substring(0, split).trim();
    final parsed = int.tryParse(value.substring(split + 1).trim());
    if (host.isEmpty || parsed == null || !_validPort(parsed)) return null;
    return Endpoint(_normalizeHost(host), parsed);
  }
  if (value.contains('/') || value.contains(' ')) return null;
  if (colonCount > 1) {
    // Bare IPv6 address without brackets. Reject host:port:extra typos that
    // also happen to contain several colons.
    final address = InternetAddress.tryParse(value);
    if (address == null || address.type != InternetAddressType.IPv6) {
      return null;
    }
    return Endpoint(value, defaultPort);
  }
  return Endpoint(_normalizeHost(value), defaultPort);
}

String _normalizeHost(String host) {
  var value = host.trim();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  return value.toLowerCase();
}

bool _validPort(int port) => port > 0 && port <= 65535;

Uri websocketUri(String host, int port) {
  final normalized = _normalizeHost(host);
  final authority = normalized.contains(':') ? '[$normalized]' : normalized;
  return Uri.parse('ws://$authority:$port/');
}

String httpDiscoveryUri(String host, int port) {
  final normalized = _normalizeHost(host);
  final authority = normalized.contains(':') ? '[$normalized]' : normalized;
  return 'http://$authority:$port/';
}

/// Derives the /24 prefixes to scan from the active network interfaces.
/// Also includes the Android emulator host alias when applicable.
List<String> localSubnetPrefixes(List<String> interfaceAddresses) {
  final prefixes = <String>{};
  for (final address in interfaceAddresses) {
    final parts = address.split('.');
    if (parts.length != 4) continue;
    if (address.startsWith('127.') || address.startsWith('169.254.')) continue;
    prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
  }
  if (prefixes.isEmpty || prefixes.any((prefix) => prefix == '10.0.2')) {
    // 10.0.2.2 is the host machine when running in the Android emulator.
    prefixes.add('10.0.2');
  }
  return prefixes.toList(growable: false)..sort();
}
