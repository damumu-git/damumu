import 'dart:typed_data';

import 'package:image/image.dart' as img;

const eventCoverWidth = 1280;
const eventCoverHeight = 960;
const eventCoverMaxBytes = 2 * 1024 * 1024;

Uint8List prepareEventCover(Uint8List source) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } catch (_) {
    throw const FormatException('eventCoverInvalid');
  }
  if (decoded == null) throw const FormatException('eventCoverInvalid');
  return _encodeCover(decoded);
}

Uint8List flipEventCover(Uint8List source) {
  final decoded = img.decodeJpg(source);
  if (decoded == null) throw const FormatException('eventCoverInvalid');
  return _encodeCover(img.flipHorizontal(decoded));
}

Uint8List _encodeCover(img.Image decoded) {
  final resized = img.copyResize(
    decoded,
    width: eventCoverWidth,
    height: eventCoverHeight,
    interpolation: img.Interpolation.linear,
  );
  for (final quality in [88, 82, 76, 70, 64]) {
    final encoded = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality),
    );
    if (encoded.length <= eventCoverMaxBytes) return encoded;
  }
  throw const FormatException('eventCoverTooLarge');
}
