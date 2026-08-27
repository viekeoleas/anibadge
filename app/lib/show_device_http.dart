import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_publish_session.dart';
import 'show_publisher.dart';

const MethodChannel _wifi = MethodChannel('znachok/wifi');

class HttpShowDevice implements ShowDevice {
  HttpShowDevice({
    this.responseTimeout = const Duration(minutes: 5),
    PublishSessionBroker? sessionBroker,
  }) : _sessionBroker = sessionBroker ?? BlePublishSessionBroker();

  final Duration responseTimeout;
  final PublishSessionBroker _sessionBroker;
  PublishSession? _session;

  String get _host => _session?.host ?? '192.168.4.1';

  Future<bool> _healthOk() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1500);
    try {
      final request = await client.getUrl(Uri.http(_host, '/health'));
      request.persistentConnection = false;
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> connect() async {
    if (!Platform.isAndroid) {
      throw const ShowPublishException(
        'BLE-публикация пока поддерживается только на Android',
      );
    }
    if (_session != null && await _healthOk()) return;
    try {
      final session = await _sessionBroker.open();
      _session = session;
      final nearby = await Permission.nearbyWifiDevices.request();
      final location = await Permission.locationWhenInUse.request();
      if (!nearby.isGranted && !location.isGranted) {
        throw const ShowPublishException(
          'Разрешите приложению подключаться к временному Wi-Fi значка',
        );
      }
      await _wifi.invokeMethod<bool>('connect', {
        'ssid': session.ssid,
        'password': session.password,
      }).timeout(const Duration(seconds: 50));

      for (var attempt = 0; attempt < 15; attempt++) {
        if (await _healthOk()) return;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      throw const ShowPublishException(
        'Wi-Fi подключён, но плата не отвечает',
      );
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      if (Platform.isAndroid) {
        await _wifi.invokeMethod<bool>('disconnect');
      }
    } catch (_) {
    } finally {
      await _sessionBroker.close();
      _session = null;
    }
  }

  @override
  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    required void Function() onTransferComplete,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    var transferComplete = false;
    try {
      final uri = Uri.http(_host, '/show/upload', {
        'name': 'current.zshow',
        'size': bytes.length.toString(),
      });
      final request = await client.postUrl(uri);
      request.persistentConnection = false;
      final boundary =
          '----znachok-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      final prefix = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="current.zshow"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      );
      final suffix = utf8.encode('\r\n--$boundary--\r\n');
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      request.contentLength = prefix.length + bytes.length + suffix.length;
      request.add(prefix);

      const chunkSize = 128 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, bytes.length);
        request.add(Uint8List.sublistView(bytes, offset, end));
        onProgress(end / bytes.length);
      }
      request.add(suffix);
      await request.flush();
      transferComplete = true;
      onTransferComplete();

      final response = await request.close().timeout(responseTimeout);
      final body = await utf8.decoder.bind(response).join();
      Map<String, dynamic> result;
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw const ShowPublishException('Плата вернула непонятный ответ');
      }
      if (response.statusCode != HttpStatus.ok || result['ok'] != true) {
        final code = result['error']?.toString() ?? 'upload-rejected';
        throw ShowPublishException(_deviceError(code));
      }
      if (result['validation'] != 'ok' || result['installed'] != true) {
        throw const ShowPublishException(
          'Плата не подтвердила проверку и установку пакета',
        );
      }
    } on TimeoutException {
      throw TimeoutException('Плата слишком долго проверяет пакет');
    } on SocketException {
      if (transferComplete && await _confirmInstalledAfterResponseLoss()) {
        return;
      }
      throw const ShowPublishException(
        'Плата получила пакет, но связь оборвалась во время его установки',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _confirmInstalledAfterResponseLoss() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      try {
        final deviceStatus = await status();
        if (deviceStatus.state == 'playing') return true;
        if (deviceStatus.state == 'error' ||
            deviceStatus.state == 'fallback') {
          return false;
        }
      } catch (_) {
        // The AP can be briefly busy while LittleFS finishes the install.
      }
    }
    return false;
  }

  @override
  Future<void> clearMedia() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.http(_host, '/show/clear'));
      request.persistentConnection = false;
      request.contentLength = 0;
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder.bind(response).join();
      Map<String, dynamic> result;
      try {
        result = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw const ShowPublishException('Плата вернула непонятный ответ');
      }
      if (response.statusCode != HttpStatus.ok || result['ok'] != true) {
        throw const ShowPublishException(
          'Плата не смогла очистить медиа-память',
        );
      }
    } on TimeoutException {
      throw const ShowPublishException('Плата не ответила на очистку памяти');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<ShowDeviceStatus> status() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.http(_host, '/show/status'));
      request.persistentConnection = false;
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw const ShowPublishException('Не удалось проверить запуск шоу');
      }
      final result = jsonDecode(body) as Map<String, dynamic>;
      return ShowDeviceStatus(
        state: result['state']?.toString() ?? 'unknown',
        installed: result['installed'] == true,
      );
    } on FormatException {
      throw const ShowPublishException('Плата вернула непонятный статус');
    } finally {
      client.close(force: true);
    }
  }
}

String _deviceError(String code) => switch (code) {
      'payload-crc' ||
      'manifest-crc' =>
        'Контрольная сумма не совпала — пакет повреждён',
      'unsupported-version' => 'Версия пакета не поддерживается прошивкой',
      'target-board' => 'Пакет собран для другой платы',
      'storage-full' => 'На плате недостаточно свободной памяти',
      'storage-clear' => 'Плата не смогла удалить предыдущее шоу',
      'storage-erase' =>
        'Плата не смогла очистить flash для нового шоу',
      'storage-memory' => 'На плате не хватило PSRAM для шоу',
      'package-size' => 'Передача оборвалась: пакет получен не полностью',
      'install-failed' => 'Плата проверила пакет, но не смогла его установить',
      _ => 'Плата отклонила пакет ($code)',
    };
