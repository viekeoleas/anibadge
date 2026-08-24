import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'show_publisher.dart';

const String publishControlServiceUuid = 'a1b20000-1111-2222-3333-444455556666';
const String publishCommandCharacteristicUuid =
    'a1b20001-1111-2222-3333-444455556666';
const String publishResponseCharacteristicUuid =
    'a1b20002-1111-2222-3333-444455556666';
const String publishDeviceName = 'Znachok-BMW';

class PublishSession {
  const PublishSession({
    required this.id,
    required this.ssid,
    required this.password,
    required this.host,
    required this.ttlSeconds,
  });

  final String id;
  final String ssid;
  final String password;
  final String host;
  final int ttlSeconds;
}

abstract interface class PublishSessionBroker {
  Future<PublishSession> open();

  Future<void> close();
}

String buildPublishControlCommand(String operation, String requestId) =>
    jsonEncode({'v': 1, 'op': operation, 'id': requestId});

PublishSession parsePublishSessionResponse(
  String source, {
  required String requestId,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    throw const ShowPublishException('Значок вернул повреждённый ответ BLE');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['v'] != 1 ||
      decoded['op'] != 'publish' ||
      decoded['id'] != requestId) {
    throw const ShowPublishException(
      'Значок использует несовместимый BLE-протокол',
    );
  }
  if (decoded['ok'] != true) {
    throw ShowPublishException(
      'Значок не смог включить временный Wi-Fi (${decoded['error'] ?? 'unknown'})',
    );
  }
  final id = decoded['session']?.toString() ?? '';
  final ssid = decoded['ssid']?.toString() ?? '';
  final password = decoded['password']?.toString() ?? '';
  final host = decoded['host']?.toString() ?? '';
  final ttl = (decoded['ttl'] as num?)?.toInt() ?? 0;
  if (id.isEmpty ||
      ssid.isEmpty ||
      password.length < 8 ||
      host.isEmpty ||
      ttl < 10) {
    throw const ShowPublishException(
      'Значок вернул неполные параметры временного Wi-Fi',
    );
  }
  return PublishSession(
    id: id,
    ssid: ssid,
    password: password,
    host: host,
    ttlSeconds: ttl,
  );
}

class BlePublishSessionBroker implements PublishSessionBroker {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  BluetoothCharacteristic? _response;
  final Uuid _uuid = const Uuid();

  @override
  Future<PublishSession> open() async {
    await close();
    if (!Platform.isAndroid) {
      throw const ShowPublishException(
        'BLE-публикация пока поддерживается только на Android',
      );
    }
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (permissions[Permission.bluetoothScan]?.isGranted != true &&
        permissions[Permission.locationWhenInUse]?.isGranted != true) {
      throw const ShowPublishException(
        'Разрешите приложению находить значок по Bluetooth',
      );
    }
    if (permissions[Permission.bluetoothConnect]?.isGranted != true) {
      throw const ShowPublishException(
        'Разрешите приложению подключаться к значку по Bluetooth',
      );
    }

    try {
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 12));
      final device = await _findDevice();
      await device.connect(
        timeout: const Duration(seconds: 15),
        mtu: null,
      );
      _device = device;
      try {
        await device.requestMtu(256);
      } catch (_) {}
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (item) => item.uuid.str128.toLowerCase() == publishControlServiceUuid,
        orElse: () => throw const ShowPublishException(
          'BLE-сервис публикации на значке не найден',
        ),
      );
      for (final characteristic in service.characteristics) {
        final uuid = characteristic.uuid.str128.toLowerCase();
        if (uuid == publishCommandCharacteristicUuid) {
          _command = characteristic;
        } else if (uuid == publishResponseCharacteristicUuid) {
          _response = characteristic;
        }
      }
      if (_command == null || _response == null) {
        throw const ShowPublishException(
          'BLE-характеристики публикации на значке не найдены',
        );
      }
      await _response!.setNotifyValue(true);
      final requestId = _newRequestId();
      final response = _waitForResponse('publish', requestId);
      await _command!.write(
        utf8.encode(buildPublishControlCommand('publish', requestId)),
        withoutResponse: false,
      );
      return parsePublishSessionResponse(
        await response.timeout(const Duration(seconds: 20)),
        requestId: requestId,
      );
    } on TimeoutException {
      await _disconnectBle();
      throw const ShowPublishException(
        'Значок не ответил по Bluetooth. Проверьте питание и повторите',
      );
    } catch (_) {
      await _disconnectBle();
      rethrow;
    }
  }

  String _newRequestId() => _uuid.v4().replaceAll('-', '').substring(0, 16);

  Future<BluetoothDevice> _findDevice() async {
    final found = Completer<BluetoothDevice>();
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final names = {
          result.device.platformName,
          result.device.advName,
          result.advertisementData.advName,
        };
        final advertisesService = result.advertisementData.serviceUuids.any(
          (uuid) => uuid.str128.toLowerCase() == publishControlServiceUuid,
        );
        if ((advertisesService || names.contains(publishDeviceName)) &&
            !found.isCompleted) {
          found.complete(result.device);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(publishControlServiceUuid)],
        timeout: const Duration(seconds: 15),
      );
      return await found.future.timeout(const Duration(seconds: 16));
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
  }

  Future<String> _waitForResponse(String operation, String requestId) =>
      _response!.onValueReceived.map((bytes) {
        final source = utf8.decode(bytes, allowMalformed: true);
        try {
          final decoded = jsonDecode(source);
          if (decoded is Map<String, dynamic> &&
              decoded['v'] == 1 &&
              decoded['op'] == operation &&
              decoded['id'] == requestId) {
            return source;
          }
        } catch (_) {}
        return '';
      }).firstWhere((value) => value.isNotEmpty);

  @override
  Future<void> close() async {
    final command = _command;
    final response = _response;
    if (command != null && response != null && _device?.isConnected == true) {
      final requestId = _newRequestId();
      try {
        final acknowledged = _waitForResponse('release', requestId);
        await command.write(
          utf8.encode(buildPublishControlCommand('release', requestId)),
          withoutResponse: false,
        );
        await acknowledged.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    await _disconnectBle();
  }

  Future<void> _disconnectBle() async {
    final device = _device;
    _command = null;
    _response = null;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect(androidDelay: 0);
      } catch (_) {}
    }
  }
}
