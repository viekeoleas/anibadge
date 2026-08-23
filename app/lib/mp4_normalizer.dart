import 'dart:io';

import 'package:flutter/services.dart';

class Mp4ImportException implements Exception {
  const Mp4ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class Mp4Normalizer {
  Future<String> normalize({
    required String sourcePath,
    required String outputDirectory,
  });
}

class AndroidMp4Normalizer implements Mp4Normalizer {
  static const MethodChannel _channel = MethodChannel('znachok/media');

  @override
  Future<String> normalize({
    required String sourcePath,
    required String outputDirectory,
  }) async {
    if (!Platform.isAndroid) {
      throw const Mp4ImportException(
        'Импорт MP4 пока поддерживается только на Android',
      );
    }
    try {
      final manifest = await _channel.invokeMethod<String>('normalizeMp4', {
        'sourcePath': sourcePath,
        'outputDirectory': outputDirectory,
      });
      if (manifest == null || manifest.isEmpty) {
        throw const Mp4ImportException(
          'Android не создал кадры из этого MP4',
        );
      }
      return manifest;
    } on PlatformException catch (error) {
      throw Mp4ImportException(
        error.message ?? 'MP4 повреждён или использует неподдерживаемый кодек',
      );
    }
  }
}
