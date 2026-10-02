import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const chatImageTargetBytes = 1500 * 1024;
const chatImageMaximumEdge = 1600;

Future<Uint8List> compressChatImage(Uint8List source) =>
    compute(_compressChatImage, source);

Uint8List _compressChatImage(Uint8List source) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    throw const FormatException('Unsupported image');
  }
  if (decoded == null) {
    throw const FormatException('Unsupported image');
  }

  var normalized = img.bakeOrientation(decoded);
  final longestEdge = normalized.width > normalized.height
      ? normalized.width
      : normalized.height;
  if (longestEdge > chatImageMaximumEdge) {
    final scale = chatImageMaximumEdge / longestEdge;
    normalized = img.copyResize(
      normalized,
      width: (normalized.width * scale).round(),
      height: (normalized.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  var opaque = _flattenOnWhite(normalized);
  for (final quality in const [76, 68, 60]) {
    final encoded = img.encodeJpg(opaque, quality: quality);
    if (encoded.length <= chatImageTargetBytes) {
      return encoded;
    }
  }

  final longestOpaqueEdge = opaque.width > opaque.height
      ? opaque.width
      : opaque.height;
  if (longestOpaqueEdge > 1200) {
    final scale = 1200 / longestOpaqueEdge;
    opaque = img.copyResize(
      opaque,
      width: (opaque.width * scale).round(),
      height: (opaque.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodeJpg(opaque, quality: 58);
}

img.Image _flattenOnWhite(img.Image source) {
  final background = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(background, source);
}
