import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const int maxGifBytes = 16 * 1024 * 1024;
const String _host = '192.168.4.1';
const String _ssid = 'Znachok-BMW';
const MethodChannel _wifi = MethodChannel('znachok/wifi');

class GifUploader {
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

  Future<void> connect() async {
    if (await _healthOk()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (await _healthOk()) return;
    if (!Platform.isAndroid) {
      throw Exception('Подключись к Wi-Fi $_ssid, пароль bmw-display');
    }

    final nearby = await Permission.nearbyWifiDevices.request();
    final location = await Permission.locationWhenInUse.request();
    if (!nearby.isGranted && !location.isGranted) {
      throw Exception('Разреши приложению подключение к ближайшим Wi-Fi сетям');
    }
    await _wifi.invokeMethod<bool>('connect', {
      'ssid': _ssid,
      'password': 'bmw-display',
    }).timeout(const Duration(seconds: 50));

    for (var attempt = 0; attempt < 15; attempt++) {
      if (await _healthOk()) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await disconnect();
    throw Exception('Плата подключена, но не отвечает');
  }

  Future<void> disconnect() async {
    if (!Platform.isAndroid) return;
    await _wifi.invokeMethod<bool>('disconnect');
  }

  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.http(_host, '/upload', {
        'name': 'current.gif',
        'size': bytes.length.toString(),
      });
      final request = await client.postUrl(uri);
      request.persistentConnection = false;
      final boundary =
          '----znachok-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
      final prefix = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="current.gif"\r\n'
        'Content-Type: image/gif\r\n\r\n',
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

      final response =
          await request.close().timeout(const Duration(minutes: 5));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Плата отклонила GIF: $body');
      }
      onProgress(1);
    } finally {
      client.close(force: true);
    }
  }
}
