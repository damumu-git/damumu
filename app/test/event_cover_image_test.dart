import 'dart:typed_data';
import 'dart:math';

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

  test(
    'horizontal flip swaps left and right without exceeding upload limit',
    () {
      final source = img.Image(width: 160, height: 120);
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 79,
        y2: 119,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.fillRect(
        source,
        x1: 80,
        y1: 0,
        x2: 159,
        y2: 119,
        color: img.ColorRgb8(0, 0, 255),
      );
      final prepared = prepareEventCover(
        Uint8List.fromList(img.encodePng(source)),
      );
      final flipped = flipEventCover(prepared);
      final image = img.decodeJpg(flipped)!;
      expect(image.getPixel(20, 20).b, greaterThan(200));
      expect(image.getPixel(1260, 20).r, greaterThan(200));
      expect(flipped.length, lessThanOrEqualTo(eventCoverMaxBytes));
    },
  );

  test('accepts a source over 2 MB and limits only the processed upload', () {
    final random = Random(17);
    final source = img.Image(width: 1000, height: 750);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
    }
    final original = Uint8List.fromList(img.encodePng(source));
    expect(original.length, greaterThan(eventCoverMaxBytes));
    final upload = prepareEventCover(original);
    expect(upload.length, lessThanOrEqualTo(eventCoverMaxBytes));
    final output = img.decodeJpg(upload)!;
    expect((output.width, output.height), (eventCoverWidth, eventCoverHeight));
  });
}
