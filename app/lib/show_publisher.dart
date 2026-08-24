import 'dart:async';
import 'dart:typed_data';

enum PublishStage {
  idle,
  connecting,
  transferring,
  verifying,
  installing,
  complete,
  failed,
}

class PublishState {
  const PublishState(this.stage, this.message, {this.progress});

  final PublishStage stage;
  final String message;
  final double? progress;
}

class ShowPublishException implements Exception {
  const ShowPublishException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ShowDeviceStatus {
  const ShowDeviceStatus({
    required this.state,
    required this.installed,
  });

  final String state;
  final bool installed;
}

abstract interface class ShowDevice {
  Future<void> connect();

  Future<void> disconnect();

  Future<void> clearMedia();

  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    required void Function() onTransferComplete,
  });

  Future<ShowDeviceStatus> status();
}

class ShowPublisher {
  ShowPublisher(
    this.device, {
    this.activationTimeout = const Duration(seconds: 12),
    this.pollInterval = const Duration(milliseconds: 150),
  });

  final ShowDevice device;
  final Duration activationTimeout;
  final Duration pollInterval;

  Future<bool> publish(
    Uint8List bytes, {
    required void Function(PublishState state) onState,
  }) async {
    try {
      onState(const PublishState(
        PublishStage.connecting,
        'Ищем значок по Bluetooth и включаем временный Wi-Fi…',
      ));
      await device.connect();

      onState(const PublishState(
        PublishStage.transferring,
        'Передача пакета…',
        progress: 0,
      ));
      await device.upload(
        bytes,
        onProgress: (progress) => onState(PublishState(
          PublishStage.transferring,
          'Передача пакета…',
          progress: progress.clamp(0, 1),
        )),
        onTransferComplete: () => onState(const PublishState(
          PublishStage.verifying,
          'Плата проверяет пакет и контрольную сумму…',
          progress: 1,
        )),
      );

      onState(const PublishState(
        PublishStage.installing,
        'Пакет установлен, запускаем анимацию…',
        progress: 1,
      ));
      final deadline = DateTime.now().add(activationTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final deviceStatus = await device.status();
        if (deviceStatus.state == 'playing') {
          onState(const PublishState(
            PublishStage.complete,
            'Готово — шоу воспроизводится на плате',
            progress: 1,
          ));
          return true;
        }
        if (deviceStatus.state == 'error' || deviceStatus.state == 'fallback') {
          throw const ShowPublishException(
            'Пакет установлен, но плата не смогла запустить воспроизведение',
          );
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException('Плата не подтвердила запуск анимации');
    } catch (error) {
      final message = switch (error) {
        ShowPublishException(:final message) => message,
        TimeoutException(:final message) =>
          message ?? 'Истекло время ожидания ответа платы',
        _ => error.toString().replaceFirst('Exception: ', ''),
      };
      onState(PublishState(
        PublishStage.failed,
        '$message. Можно повторить публикацию.',
      ));
      return false;
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}
