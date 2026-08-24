import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:znachok_bmw/show_publisher.dart';

void main() {
  test('success crosses every publish stage in order', () async {
    final device = FakeShowDevice();
    final states = <PublishState>[];
    final result = await ShowPublisher(
      device,
      pollInterval: Duration.zero,
    ).publish(Uint8List(64), onState: states.add);

    expect(result, isTrue);
    expect(
      states.map((state) => state.stage),
      containsAllInOrder([
        PublishStage.connecting,
        PublishStage.transferring,
        PublishStage.verifying,
        PublishStage.installing,
        PublishStage.complete,
      ]),
    );
    expect(states.last.progress, 1);
    expect(device.disconnectCalls, 1);
  });

  test('checksum rejection becomes a retryable failure', () async {
    final device = FakeShowDevice(
      uploadOutcomes: [
        const ShowPublishException(
          'Контрольная сумма не совпала — пакет повреждён',
        ),
      ],
    );
    final states = <PublishState>[];
    final result = await ShowPublisher(device).publish(
      Uint8List(64),
      onState: states.add,
    );

    expect(result, isFalse);
    expect(
        states.map((state) => state.stage), contains(PublishStage.verifying));
    expect(states.last.stage, PublishStage.failed);
    expect(states.last.message, contains('Контрольная сумма'));
    expect(states.last.message, contains('повторить'));
    expect(device.statusCalls, 0);
    expect(device.disconnectCalls, 1);
  });

  test('transport timeout becomes a clear retryable failure', () async {
    final device = FakeShowDevice(
      uploadOutcomes: [TimeoutException('Передача прервана по timeout')],
    );
    final states = <PublishState>[];
    final result = await ShowPublisher(device).publish(
      Uint8List(64),
      onState: states.add,
    );

    expect(result, isFalse);
    expect(states.last.stage, PublishStage.failed);
    expect(states.last.message, contains('timeout'));
    expect(states.last.message, contains('повторить'));
  });

  test('retry republishes the same package and succeeds', () async {
    final device = FakeShowDevice(
      uploadOutcomes: [
        const ShowPublishException('Первый запрос оборвался'),
        null,
      ],
    );
    final publisher = ShowPublisher(device, pollInterval: Duration.zero);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final firstStates = <PublishState>[];
    final secondStates = <PublishState>[];

    expect(await publisher.publish(bytes, onState: firstStates.add), isFalse);
    expect(await publisher.publish(bytes, onState: secondStates.add), isTrue);
    expect(device.connectCalls, 2);
    expect(device.uploadCalls, 2);
    expect(device.disconnectCalls, 2);
    expect(secondStates.last.stage, PublishStage.complete);
  });
}

class FakeShowDevice implements ShowDevice {
  FakeShowDevice({List<Object?>? uploadOutcomes})
      : uploadOutcomes = uploadOutcomes ?? [null];

  final List<Object?> uploadOutcomes;
  int connectCalls = 0;
  int uploadCalls = 0;
  int statusCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<void> clearMedia() async {}

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> upload(
    Uint8List bytes, {
    required void Function(double progress) onProgress,
    required void Function() onTransferComplete,
  }) async {
    onProgress(0.5);
    onProgress(1);
    onTransferComplete();
    final outcome = uploadOutcomes[uploadCalls++];
    if (outcome != null) throw outcome;
  }

  @override
  Future<ShowDeviceStatus> status() async {
    statusCalls++;
    return const ShowDeviceStatus(state: 'playing', installed: true);
  }
}
