import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

/// Quality ladder shared by every show frame encoder: start visually clean and
/// only degrade when the frame does not fit the player budget.
const List<int> showJpegQualityLadder = [88, 82, 76, 68, 60, 52, 44, 36];

/// Hard per-frame byte budget of the ZSHOW v1 player.
const int showJpegFrameBudget = 212 * 1024;

const MethodChannel _media = MethodChannel('znachok/media');

/// The native encoder disappears only when the platform has no plugin at all
/// (tests, desktop); a transient encode error must not disable it forever.
bool _nativeEncoderAvailable = true;

/// Encodes one RGBA frame into a baseline JPEG no larger than [maxBytes].
///
/// Prefers the Android encoder (libjpeg-turbo via `Bitmap.compress`) exposed
/// on the `znachok/media` channel and falls back to the pure-Dart encoder
/// where the channel is not available. Returns null when even the lowest
/// quality of the ladder exceeds the budget.
Future<Uint8List?> encodeRgbaJpegUnderBudget({
  required Uint8List rgba,
  required int width,
  required int height,
  int maxBytes = showJpegFrameBudget,
  List<int> qualities = showJpegQualityLadder,
}) async {
  if (_nativeEncoderAvailable) {
    try {
      return await _media.invokeMethod<Uint8List>('encodeJpeg', {
        'rgba': rgba,
        'width': width,
        'height': height,
        'maxBytes': maxBytes,
        'qualities': qualities,
      });
    } on MissingPluginException {
      _nativeEncoderAvailable = false;
    } on PlatformException catch (error) {
      if (error.code == 'TOO_COMPLEX') return null;
      // Any other native failure: encode this frame in Dart instead.
    }
  }
  final frame = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    order: image.ChannelOrder.rgba,
  );
  for (final quality in qualities) {
    final encoded = image.encodeJpg(
      frame,
      quality: quality,
      chroma: image.JpegChroma.yuv420,
    );
    if (encoded.length <= maxBytes) return encoded;
  }
  return null;
}
