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

  for (final edge in const [1200, 960, 720]) {
    final longestOpaqueEdge = opaque.width > opaque.height
        ? opaque.width
        : opaque.height;
    if (longestOpaqueEdge > edge) {
      final scale = edge / longestOpaqueEdge;
      opaque = img.copyResize(
        opaque,
        width: (opaque.width * scale).round(),
        height: (opaque.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    for (final quality in const [58, 50, 42]) {
      final encoded = img.encodeJpg(opaque, quality: quality);
      if (encoded.length <= chatImageTargetBytes) return encoded;
    }
  }
  throw const FormatException('Compressed image exceeds limit');
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
