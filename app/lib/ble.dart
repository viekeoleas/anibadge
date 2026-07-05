import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// UUID-ы должны совпадать с прошивкой (main.cpp).
const String kSvc = "a1b20000-1111-2222-3333-444455556666";
const String kCtrl = "a1b20001-1111-2222-3333-444455556666";
const String kData = "a1b20002-1111-2222-3333-444455556666";
const String kDevName = "Znachok-BMW";

/// Обёртка над BLE-соединением со знаком.
class Znachok {
  BluetoothDevice? _dev;
  BluetoothCharacteristic? _ctrl;
  BluetoothCharacteristic? _data;
  StreamSubscription? _notifySub;
  String _lastNotify = "";
  int _chunk = 180;

  bool get connected => _dev != null && _dev!.isConnected;

  /// Найти и подключиться к знаку. onState — текстовый статус для UI.
  Future<void> connect({void Function(String)? onState}) async {
    onState?.call("Поиск устройства…");
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first;

    final completer = Completer<BluetoothDevice>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final names = {
          r.device.platformName,
          r.device.advName,
          r.advertisementData.advName,
        };
        if (names.contains(kDevName) && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });
    // Ищем по имени (без фильтра по сервису: 128-битный UUID может не попасть
    // в основной рекламный пакет, тогда OS-фильтр не находит плату).
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );
    BluetoothDevice dev;
    try {
      dev = await completer.future.timeout(const Duration(seconds: 16));
    } on TimeoutException {
      throw Exception('Плата не найдена. Проверь, что она включена и Bluetooth на телефоне активен.');
    } finally {
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    }

    onState?.call("Подключение…");
    await dev.connect(timeout: const Duration(seconds: 15));
    _dev = dev;

    if (Platform.isAndroid) {
      try {
        final mtu = await dev.requestMtu(517);
        _chunk = (mtu - 3).clamp(20, 512);
      } catch (_) {}
    }

    final services = await dev.discoverServices();
    final svc = services.firstWhere((s) => s.uuid.str128.toLowerCase() == kSvc);
    for (final c in svc.characteristics) {
      final u = c.uuid.str128.toLowerCase();
      if (u == kCtrl) _ctrl = c;
      if (u == kData) _data = c;
    }
    if (_ctrl == null || _data == null) {
      throw Exception("характеристики не найдены");
    }

    await _ctrl!.setNotifyValue(true);
    _notifySub = _ctrl!.onValueReceived.listen((v) {
      _lastNotify = utf8.decode(v, allowMalformed: true);
    });
    onState?.call("Подключено");
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _dev?.disconnect();
    _dev = null;
    _ctrl = _data = null;
  }

  Future<void> _send(String cmd) =>
      _ctrl!.write(utf8.encode(cmd), withoutResponse: false);

  /// Дождаться нотификации с одним из префиксов.
  Future<String> _waitFor(List<String> prefixes,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final t0 = DateTime.now();
    while (DateTime.now().difference(t0) < timeout) {
      for (final p in prefixes) {
        if (_lastNotify == p || _lastNotify.startsWith(p)) return _lastNotify;
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }
    throw TimeoutException("нет ответа от знака");
  }

  /// Список файлов на устройстве.
  Future<List<String>> list() async {
    _lastNotify = "";
    await _send("LIST");
    final r = await _waitFor(["LIST:"]);
    final csv = r.substring(5);
    return csv.isEmpty ? [] : csv.split(",");
  }

  Future<void> show(String name) => _send("SHOW:$name");
  Future<void> remove(String name) async {
    _lastNotify = "";
    await _send("DEL:$name");
    final r = await _waitFor(["OK", "ERR"]);
    if (r == "ERR") throw Exception("устройство не удалило файл");
  }

  /// Залить файл. onProgress: 0..1.
  Future<void> upload(String name, Uint8List bytes,
      {void Function(double)? onProgress}) async {
    _lastNotify = "";
    await _send("BEGIN:$name:${bytes.length}");
    await _waitFor(["OK", "ERR"]);
    if (_lastNotify == "ERR") throw Exception("устройство отклонило приём");

    for (int off = 0; off < bytes.length; off += _chunk) {
      final end = (off + _chunk < bytes.length) ? off + _chunk : bytes.length;
      await _data!.write(bytes.sublist(off, end), withoutResponse: true);
      onProgress?.call(end / bytes.length);
      if ((off ~/ _chunk) % 24 == 0) {
        await Future.delayed(const Duration(milliseconds: 8));
      }
    }

    _lastNotify = "";
    await _send("END");
    final r = await _waitFor(["DONE", "ERR"]);
    onProgress?.call(1.0);
    if (r == "ERR") throw Exception("ошибка передачи (битый файл)");
  }
}
