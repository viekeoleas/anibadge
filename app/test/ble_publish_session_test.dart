import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:znachok_bmw/ble_publish_session.dart';
import 'package:znachok_bmw/show_publisher.dart';

void main() {
  test('publish command is a versioned and correlatable envelope', () {
    final decoded = jsonDecode(
      buildPublishControlCommand('publish', 'request-7'),
    ) as Map<String, dynamic>;

    expect(decoded, {
      'v': 1,
      'op': 'publish',
      'id': 'request-7',
    });
  });

  test('valid BLE response supplies a temporary Wi-Fi session', () {
    final session = parsePublishSessionResponse(
      jsonEncode({
        'v': 1,
        'op': 'publish',
        'id': 'request-7',
        'ok': true,
        'session': 'session-a',
        'ssid': 'Znachok-D24F',
        'password': 'temporary-pass',
        'host': '192.168.4.1',
        'ttl': 180,
      }),
      requestId: 'request-7',
    );

    expect(session.id, 'session-a');
    expect(session.ssid, 'Znachok-D24F');
    expect(session.password, 'temporary-pass');
    expect(session.host, '192.168.4.1');
    expect(session.ttlSeconds, 180);
  });

  test('response from another request is rejected', () {
    expect(
      () => parsePublishSessionResponse(
        jsonEncode({
          'v': 1,
          'op': 'publish',
          'id': 'stale-request',
          'ok': true,
          'session': 'session-a',
          'ssid': 'Znachok-D24F',
          'password': 'temporary-pass',
          'host': '192.168.4.1',
          'ttl': 180,
        }),
        requestId: 'request-7',
      ),
      throwsA(isA<ShowPublishException>()),
    );
  });

  test('firmware Wi-Fi failure is actionable', () {
    expect(
      () => parsePublishSessionResponse(
        jsonEncode({
          'v': 1,
          'op': 'publish',
          'id': 'request-7',
          'ok': false,
          'error': 'wifi-start',
        }),
        requestId: 'request-7',
      ),
      throwsA(
        isA<ShowPublishException>().having(
          (error) => error.message,
          'message',
          contains('wifi-start'),
        ),
      ),
    );
  });
}
