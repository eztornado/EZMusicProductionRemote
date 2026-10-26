import 'package:ezmusicproduction_remote/core/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEndpointInput', () {
    test('accepts a plain host and applies the default port', () {
      final endpoint = parseEndpointInput('Studio.local');
      expect(endpoint?.host, 'studio.local');
      expect(endpoint?.port, 47823);
    });

    test('accepts host:port and websocket URLs', () {
      expect(parseEndpointInput('192.168.1.20:5000')?.port, 5000);
      expect(parseEndpointInput('ws://192.168.1.20:5000/')?.port, 5000);
      expect(parseEndpointInput('http://192.168.1.20/')?.port, 47823);
    });

    test('rejects TLS URLs because the remote API is LAN-only ws://', () {
      expect(parseEndpointInput('wss://192.168.1.20:47823/'), isNull);
      expect(parseEndpointInput('https://192.168.1.20/'), isNull);
    });

    test('accepts bracketed and bare IPv6 hosts', () {
      expect(parseEndpointInput('[fe80::1]:47823')?.host, 'fe80::1');
      expect(parseEndpointInput('fe80::1')?.host, 'fe80::1');
      expect(parseEndpointInput('[2001:db8::1]')?.port, 47823);
    });

    test('rejects empty, malformed and out-of-range input', () {
      expect(parseEndpointInput(''), isNull);
      expect(parseEndpointInput('host with spaces'), isNull);
      expect(parseEndpointInput('host:0'), isNull);
      expect(parseEndpointInput('host:70000'), isNull);
      expect(parseEndpointInput('host:abc'), isNull);
      expect(parseEndpointInput('host:'), isNull);
      expect(parseEndpointInput(':47823'), isNull);
      expect(parseEndpointInput('[]:47823'), isNull);
      expect(parseEndpointInput('[not-ipv6]:47823'), isNull);
      expect(parseEndpointInput('host:47823:extra'), isNull);
      expect(parseEndpointInput('fe80::1/path'), isNull);
      expect(parseEndpointInput('ftp://host/'), isNull);
    });
  });

  test('websocketUri brackets IPv6 authorities', () {
    expect(websocketUri('fe80::1', 47823).toString(), 'ws://[fe80::1]:47823/');
    expect(
      websocketUri('Studio.local', 47823).toString(),
      'ws://studio.local:47823/',
    );
  });

  test('localSubnetPrefixes derives /24 candidates', () {
    expect(localSubnetPrefixes(const ['192.168.1.20', '10.0.0.5']), <String>[
      '10.0.0',
      '192.168.1',
    ]);
    expect(localSubnetPrefixes(const <String>[]), <String>['10.0.2']);
    expect(localSubnetPrefixes(const ['10.0.2.15']), <String>['10.0.2']);
    expect(localSubnetPrefixes(const ['127.0.0.1', '169.254.10.2']), <String>[
      '10.0.2',
    ]);
  });
}
