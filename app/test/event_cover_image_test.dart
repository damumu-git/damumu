import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zaihandazi/event_cover_image.dart';

void main() {
  test('normalizes a cropped photo to the upload contract', () {
    final source = img.Image(width: 160, height: 120);
    img.fill(source, color: img.ColorRgb8(240, 120, 80));
    final bytes = prepareEventCover(Uint8List.fromList(img.encodePng(source)));
    final result = img.decodeJpg(bytes)!;
    expect(result.width, eventCoverWidth);
    expect(result.height, eventCoverHeight);
    expect(bytes.length, lessThanOrEqualTo(eventCoverMaxBytes));
  });

  test('rejects unsupported image data', () {
    expect(
      () => prepareEventCover(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
